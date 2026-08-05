package blog

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	MediaURLPrefix = "/media/blog"
	commitMarker   = ".commit-target"
	backupPrefix   = ".backup-"
	stagingPrefix  = ".post-"
)

var (
	ErrInvalidSlug  = errors.New("invalid blog slug")
	ErrInvalidAsset = errors.New("invalid blog asset path")
	ErrNotPublished = errors.New("blog post is not published")
	ErrPostExists   = errors.New("blog post already exists")
	slugPattern     = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)
	extPattern      = regexp.MustCompile(`^\.[A-Za-z0-9]+$`)
)

type Metadata struct {
	ID          string `json:"id"`
	Slug        string `json:"slug"`
	Title       string `json:"title"`
	Language    string `json:"language"`
	Status      string `json:"status"`
	PublishedAt string `json:"publishedAt"`
	UpdatedAt   string `json:"updatedAt"`
	CreatedAt   string `json:"createdAt"`
	Author      string `json:"author"`
}

type Document struct {
	Metadata Metadata
	Markdown string
}

type SaveInput struct {
	Title       string
	Slug        string
	Language    string
	Status      string
	PublishedAt string
	Markdown    string
}

type UploadResult struct {
	URL      string `json:"url"`
	Markdown string `json:"markdown"`
}

type Store struct {
	root          string
	defaultAuthor string
	mu            sync.RWMutex
	now           func() time.Time
}

func NewStore(root, defaultAuthor string) (*Store, error) {
	if strings.TrimSpace(root) == "" {
		return nil, errors.New("blog root is required")
	}
	absoluteRoot, err := filepath.Abs(root)
	if err != nil {
		return nil, fmt.Errorf("resolve blog root: %w", err)
	}
	if err := os.MkdirAll(absoluteRoot, 0o755); err != nil {
		return nil, fmt.Errorf("create blog root: %w", err)
	}
	store := &Store{root: absoluteRoot, defaultAuthor: defaultAuthor, now: time.Now}
	if err := store.recoverDirectories(); err != nil {
		return nil, err
	}
	return store, nil
}

func Slugify(value string) string {
	var slug strings.Builder
	previousDash := false
	for _, r := range value {
		if r >= 'A' && r <= 'Z' {
			r += 'a' - 'A'
		}
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' {
			slug.WriteRune(r)
			previousDash = false
			continue
		}
		if slug.Len() > 0 && !previousDash {
			slug.WriteByte('-')
			previousDash = true
		}
	}
	return strings.Trim(slug.String(), "-")
}

func (store *Store) List(includeDrafts bool) ([]Metadata, error) {
	store.mu.RLock()
	defer store.mu.RUnlock()

	entries, err := os.ReadDir(store.root)
	if errors.Is(err, fs.ErrNotExist) {
		return []Metadata{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("list blog root: %w", err)
	}

	posts := make([]Metadata, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() || !validSlug(entry.Name()) {
			continue
		}
		metadata, err := store.loadMetadata(entry.Name())
		if err != nil {
			slog.Warn("skipping invalid blog metadata", "slug", entry.Name(), "error", err)
			continue
		}
		if includeDrafts || metadata.Status == "published" {
			posts = append(posts, metadata)
		}
	}
	sort.SliceStable(posts, func(i, j int) bool {
		return sortTime(posts[i]).After(sortTime(posts[j]))
	})
	return posts, nil
}

func (store *Store) Load(slug string, includeDrafts bool) (Document, error) {
	store.mu.RLock()
	defer store.mu.RUnlock()
	return store.load(slug, includeDrafts)
}

func (store *Store) OpenPublishedAsset(slug, assetPath string) (*os.File, error) {
	store.mu.RLock()
	defer store.mu.RUnlock()

	if !validSlug(slug) {
		return nil, ErrInvalidSlug
	}
	if !fs.ValidPath(assetPath) || assetPath == "." {
		return nil, ErrInvalidAsset
	}
	metadata, err := store.loadMetadata(slug)
	if err != nil {
		return nil, err
	}
	if metadata.Status != "published" {
		return nil, ErrNotPublished
	}
	root, err := os.OpenRoot(store.root)
	if err != nil {
		return nil, fmt.Errorf("open blog root: %w", err)
	}
	defer root.Close()
	file, err := root.Open(filepath.ToSlash(filepath.Join(slug, "assets", filepath.FromSlash(assetPath))))
	if err != nil {
		return nil, fmt.Errorf("open blog asset: %w", err)
	}
	return file, nil
}

func (store *Store) Save(input SaveInput, oldSlug string) (string, error) {
	store.mu.Lock()
	defer store.mu.Unlock()

	title := strings.TrimSpace(input.Title)
	if title == "" {
		return "", errors.New("title is required")
	}
	newSlug := Slugify(strings.TrimSpace(input.Slug))
	if newSlug == "" {
		newSlug = "post-" + randomToken(8)
	}
	if !validSlug(newSlug) {
		return "", ErrInvalidSlug
	}
	if oldSlug != "" && !validSlug(oldSlug) {
		return "", ErrInvalidSlug
	}

	status := normalizeStatus(input.Status)
	language := strings.TrimSpace(input.Language)
	if language != "en" && language != "fr" {
		return "", errors.New("language must be en or fr")
	}
	publishedAt, err := ParseLocalDateTime(input.PublishedAt)
	if err != nil {
		return "", err
	}

	existing := Document{}
	if oldSlug != "" {
		existing, err = store.load(oldSlug, true)
		if err != nil && !errors.Is(err, fs.ErrNotExist) {
			return "", err
		}
	}
	if oldSlug == "" || oldSlug != newSlug {
		if _, err := os.Stat(store.metadataPath(newSlug)); err == nil {
			return "", fmt.Errorf("%w: %s", ErrPostExists, newSlug)
		} else if !errors.Is(err, fs.ErrNotExist) {
			return "", fmt.Errorf("check blog post: %w", err)
		}
	}

	now := store.now().UTC().Format(time.RFC3339)
	createdAt := existing.Metadata.CreatedAt
	if createdAt == "" {
		createdAt = now
	}
	published := ""
	if !publishedAt.IsZero() {
		published = publishedAt.Format(time.RFC3339)
	}
	if status == "published" && published == "" {
		published = existing.Metadata.PublishedAt
		if published == "" {
			published = createdAt
		}
	}
	markdownSource := NormalizeMarkdown(input.Markdown)
	if oldSlug != "" && oldSlug != newSlug {
		markdownSource = strings.ReplaceAll(markdownSource, MediaURLPrefix+"/"+oldSlug+"/", MediaURLPrefix+"/"+newSlug+"/")
	}

	metadata := Metadata{
		ID: existing.Metadata.ID, Slug: newSlug, Title: title, Language: language, Status: status,
		PublishedAt: published, UpdatedAt: now, CreatedAt: createdAt, Author: store.defaultAuthor,
	}
	if metadata.ID == "" {
		metadata.ID = newSlug
	}
	encoded, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		return "", fmt.Errorf("encode blog metadata: %w", err)
	}
	encoded = append(encoded, '\n')

	if err := os.MkdirAll(store.root, 0o755); err != nil {
		return "", fmt.Errorf("create blog root: %w", err)
	}
	stagingDirectory, err := os.MkdirTemp(store.root, stagingPrefix+"*")
	if err != nil {
		return "", fmt.Errorf("stage blog post: %w", err)
	}
	defer os.RemoveAll(stagingDirectory)
	oldDirectory := store.postDirectory(oldSlug)
	if oldSlug != "" {
		if err := copyAssets(filepath.Join(oldDirectory, "assets"), filepath.Join(stagingDirectory, "assets")); err != nil {
			return "", fmt.Errorf("stage old blog assets: %w", err)
		}
	}
	if oldSlug != newSlug {
		if err := copyAssets(filepath.Join(store.postDirectory(newSlug), "assets"), filepath.Join(stagingDirectory, "assets")); err != nil {
			return "", fmt.Errorf("stage uploaded blog assets: %w", err)
		}
	}
	if err := atomicWrite(filepath.Join(stagingDirectory, "post.json"), encoded, 0o644); err != nil {
		return "", fmt.Errorf("write blog metadata: %w", err)
	}
	if err := atomicWrite(filepath.Join(stagingDirectory, "content.md"), []byte(markdownSource), 0o644); err != nil {
		return "", fmt.Errorf("write blog markdown: %w", err)
	}
	if err := store.commitPostDirectory(stagingDirectory, oldSlug, newSlug); err != nil {
		return "", err
	}
	return newSlug, nil
}

func (store *Store) commitPostDirectory(stagingDirectory, oldSlug, newSlug string) error {
	oldDirectory := store.postDirectory(oldSlug)
	newDirectory := store.postDirectory(newSlug)
	oldBackup := filepath.Join(store.root, backupPrefix+"old-"+randomToken(8))
	newBackup := filepath.Join(store.root, backupPrefix+"new-"+randomToken(8))
	hasOld := false
	hasNew := false
	if oldSlug != "" {
		if _, err := os.Stat(oldDirectory); err == nil {
			hasOld = true
			if err := writeCommitMarker(oldDirectory, newSlug); err != nil {
				return fmt.Errorf("mark blog post commit: %w", err)
			}
			if err := os.Rename(oldDirectory, oldBackup); err != nil {
				_ = os.Remove(filepath.Join(oldDirectory, commitMarker))
				return fmt.Errorf("backup blog post: %w", err)
			}
		} else if !errors.Is(err, fs.ErrNotExist) {
			return fmt.Errorf("check old blog post: %w", err)
		}
	}
	if oldSlug != newSlug {
		if _, err := os.Stat(newDirectory); err == nil {
			hasNew = true
			if err := writeCommitMarker(newDirectory, newSlug); err != nil {
				if hasOld {
					_ = os.Rename(oldBackup, oldDirectory)
					_ = os.Remove(filepath.Join(oldDirectory, commitMarker))
				}
				return fmt.Errorf("mark uploaded blog assets: %w", err)
			}
			if err := os.Rename(newDirectory, newBackup); err != nil {
				_ = os.Remove(filepath.Join(newDirectory, commitMarker))
				if hasOld {
					_ = os.Rename(oldBackup, oldDirectory)
					_ = os.Remove(filepath.Join(oldDirectory, commitMarker))
				}
				return fmt.Errorf("backup uploaded blog assets: %w", err)
			}
		} else if !errors.Is(err, fs.ErrNotExist) {
			if hasOld {
				_ = os.Rename(oldBackup, oldDirectory)
				_ = os.Remove(filepath.Join(oldDirectory, commitMarker))
			}
			return fmt.Errorf("check destination blog post: %w", err)
		}
	}
	if err := os.Rename(stagingDirectory, newDirectory); err != nil {
		if hasNew {
			_ = os.Rename(newBackup, newDirectory)
			_ = os.Remove(filepath.Join(newDirectory, commitMarker))
		}
		if hasOld {
			_ = os.Rename(oldBackup, oldDirectory)
			_ = os.Remove(filepath.Join(oldDirectory, commitMarker))
		}
		return fmt.Errorf("commit blog post: %w", err)
	}
	for _, backup := range []struct {
		exists bool
		path   string
	}{{hasOld, oldBackup}, {hasNew, newBackup}} {
		if backup.exists {
			if err := os.RemoveAll(backup.path); err != nil {
				slog.Warn("could not remove blog post backup", "path", backup.path, "error", err)
			}
		}
	}
	directory, err := os.Open(store.root)
	if err != nil {
		slog.Warn("could not open blog root after commit", "path", store.root, "error", err)
		return nil
	}
	defer directory.Close()
	if err := directory.Sync(); err != nil {
		slog.Warn("could not sync blog root after commit", "path", store.root, "error", err)
	}
	return nil
}

func writeCommitMarker(directory, targetSlug string) error {
	return atomicWrite(filepath.Join(directory, commitMarker), []byte(targetSlug+"\n"), 0o600)
}

func (store *Store) recoverDirectories() error {
	entries, err := os.ReadDir(store.root)
	if err != nil {
		return fmt.Errorf("inspect blog recovery state: %w", err)
	}
	for _, entry := range entries {
		name := entry.Name()
		fullPath := filepath.Join(store.root, name)
		if entry.IsDir() && strings.HasPrefix(name, stagingPrefix) {
			if err := os.RemoveAll(fullPath); err != nil {
				return fmt.Errorf("remove abandoned blog staging directory: %w", err)
			}
			continue
		}
		if entry.IsDir() && strings.HasPrefix(name, backupPrefix) {
			if err := store.recoverBackup(fullPath); err != nil {
				return err
			}
			continue
		}
		if entry.IsDir() && validSlug(name) {
			_ = os.Remove(filepath.Join(fullPath, commitMarker))
		}
	}
	return nil
}

func (store *Store) recoverBackup(backupDirectory string) error {
	marker, err := os.ReadFile(filepath.Join(backupDirectory, commitMarker))
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read blog recovery marker: %w", err)
	}
	targetSlug := strings.TrimSpace(string(marker))
	if !validSlug(targetSlug) {
		return fmt.Errorf("blog recovery marker has invalid target %q", targetSlug)
	}
	if _, err := os.Stat(store.postDirectory(targetSlug)); err == nil {
		return os.RemoveAll(backupDirectory)
	} else if !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("check recovered blog target: %w", err)
	}
	restoreSlug := targetSlug
	if content, err := os.ReadFile(filepath.Join(backupDirectory, "post.json")); err == nil {
		var metadata Metadata
		if json.Unmarshal(content, &metadata) == nil && validSlug(metadata.Slug) {
			restoreSlug = metadata.Slug
		}
	}
	restoreDirectory := store.postDirectory(restoreSlug)
	if _, err := os.Stat(restoreDirectory); err == nil {
		return os.RemoveAll(backupDirectory)
	} else if !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("check blog recovery destination: %w", err)
	}
	if err := os.Remove(filepath.Join(backupDirectory, commitMarker)); err != nil {
		return fmt.Errorf("remove blog recovery marker: %w", err)
	}
	if err := os.Rename(backupDirectory, restoreDirectory); err != nil {
		return fmt.Errorf("recover blog directory: %w", err)
	}
	slog.Warn("recovered interrupted blog commit", "slug", restoreSlug)
	return nil
}

func copyAssets(source, destination string) error {
	return fs.WalkDir(os.DirFS(source), ".", func(name string, entry fs.DirEntry, walkErr error) error {
		if errors.Is(walkErr, fs.ErrNotExist) && name == "." {
			return nil
		}
		if walkErr != nil {
			return walkErr
		}
		if name == "." {
			return os.MkdirAll(destination, 0o755)
		}
		target := filepath.Join(destination, filepath.FromSlash(name))
		if entry.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		if !entry.Type().IsRegular() {
			return fmt.Errorf("asset %q is not a regular file", name)
		}
		content, err := os.ReadFile(filepath.Join(source, filepath.FromSlash(name)))
		if err != nil {
			return err
		}
		return atomicWrite(target, content, 0o644)
	})
}

func (store *Store) Upload(slug, filename, mimeType string, data []byte) (UploadResult, error) {
	store.mu.Lock()
	defer store.mu.Unlock()

	if !validSlug(slug) {
		return UploadResult{}, ErrInvalidSlug
	}
	extension := mimeExtension(mimeType)
	if !extPattern.MatchString(extension) {
		return UploadResult{}, errors.New("unsupported image type")
	}
	stem := Slugify(strings.TrimSuffix(filepath.Base(filename), filepath.Ext(filepath.Base(filename))))
	if stem == "" {
		stem = "image"
	}
	assetName := stem + "-" + randomToken(8) + extension
	assetsDirectory := filepath.Join(store.postDirectory(slug), "assets")
	if err := os.MkdirAll(assetsDirectory, 0o755); err != nil {
		return UploadResult{}, fmt.Errorf("create assets directory: %w", err)
	}
	if err := atomicWrite(filepath.Join(assetsDirectory, assetName), data, 0o644); err != nil {
		return UploadResult{}, fmt.Errorf("write image: %w", err)
	}
	url := MediaURLPrefix + "/" + slug + "/assets/" + assetName
	return UploadResult{URL: url, Markdown: "![" + stem + "](" + url + ")"}, nil
}

func (store *Store) load(slug string, includeDrafts bool) (Document, error) {
	if !validSlug(slug) {
		return Document{}, ErrInvalidSlug
	}
	metadata, err := store.loadMetadata(slug)
	if err != nil {
		return Document{}, err
	}
	if !includeDrafts && metadata.Status != "published" {
		return Document{}, ErrNotPublished
	}
	content, err := os.ReadFile(store.contentPath(slug))
	if err != nil {
		return Document{}, fmt.Errorf("read blog markdown: %w", err)
	}
	return Document{Metadata: metadata, Markdown: string(content)}, nil
}

func (store *Store) loadMetadata(slug string) (Metadata, error) {
	content, err := os.ReadFile(store.metadataPath(slug))
	if err != nil {
		return Metadata{}, fmt.Errorf("read blog metadata: %w", err)
	}
	var metadata Metadata
	if err := json.Unmarshal(content, &metadata); err != nil {
		return Metadata{}, fmt.Errorf("decode blog metadata: %w", err)
	}
	if metadata.Author == "" {
		metadata.Author = store.defaultAuthor
	}
	if metadata.Language != "en" && metadata.Language != "fr" {
		return Metadata{}, errors.New("blog metadata has an invalid language")
	}
	metadata.Status = normalizeStatus(metadata.Status)
	return metadata, nil
}

func (store *Store) postDirectory(slug string) string { return filepath.Join(store.root, slug) }
func (store *Store) metadataPath(slug string) string {
	return filepath.Join(store.postDirectory(slug), "post.json")
}
func (store *Store) contentPath(slug string) string {
	return filepath.Join(store.postDirectory(slug), "content.md")
}

func validSlug(slug string) bool { return slugPattern.MatchString(slug) }

func normalizeStatus(status string) string {
	if strings.TrimSpace(status) == "published" {
		return "published"
	}
	return "draft"
}

func sortTime(metadata Metadata) time.Time {
	for _, value := range []string{metadata.PublishedAt, metadata.UpdatedAt, metadata.CreatedAt} {
		if value == "" {
			continue
		}
		parsed, err := time.Parse(time.RFC3339Nano, value)
		if err == nil {
			return parsed
		}
		return time.Time{}
	}
	return time.Time{}
}

func mimeExtension(mimeType string) string {
	switch mimeType {
	case "image/png":
		return ".png"
	case "image/jpeg":
		return ".jpg"
	case "image/webp":
		return ".webp"
	case "image/gif":
		return ".gif"
	case "image/svg+xml":
		return ".svg"
	default:
		return ""
	}
}

func randomToken(length int) string {
	const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	buffer := make([]byte, length)
	if _, err := rand.Read(buffer); err != nil {
		panic(fmt.Sprintf("read random data: %v", err))
	}
	for index := range buffer {
		buffer[index] = alphabet[int(buffer[index])%len(alphabet)]
	}
	return string(buffer)
}

func atomicWrite(path string, data []byte, mode fs.FileMode) error {
	temporary, err := os.CreateTemp(filepath.Dir(path), ".blog-*")
	if err != nil {
		return err
	}
	temporaryName := temporary.Name()
	defer func() {
		_ = temporary.Close()
		_ = os.Remove(temporaryName)
	}()
	if err := temporary.Chmod(mode); err != nil {
		return err
	}
	if _, err := temporary.Write(data); err != nil {
		return err
	}
	if err := temporary.Sync(); err != nil {
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryName, path); err != nil {
		return err
	}
	directory, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}
