package blog

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// A conflict is a post that both the repository and the admin changed since the last merge. MergeSeed keeps the
// site version and writes the repository version next to it, as post.seed.json and content.seed.md. The admin
// resolves it: it takes the repository version, or keeps the site version.

const (
	seedMetadataName = "post.seed.json"
	seedContentName  = "content.seed.md"
)

var ErrNoConflict = errors.New("this blogpost has no conflict with the repository")

// Conflict holds the two versions of a post in conflict.
type Conflict struct {
	Site       Document
	Repository Document
}

// HasConflict reports whether a post waits for a conflict resolution.
func (store *Store) HasConflict(slug string) bool {
	if !validSlug(slug) {
		return false
	}
	store.mu.RLock()
	defer store.mu.RUnlock()
	_, err := store.readSeedVersion(slug)
	return err == nil
}

// Conflict loads both versions of a post in conflict, drafts included.
func (store *Store) Conflict(slug string) (Conflict, error) {
	if !validSlug(slug) {
		return Conflict{}, ErrInvalidSlug
	}
	store.mu.RLock()
	defer store.mu.RUnlock()
	site, err := store.load(slug, true)
	if err != nil {
		return Conflict{}, err
	}
	repository, err := store.readSeedVersion(slug)
	if err != nil {
		return Conflict{}, err
	}
	return Conflict{Site: site, Repository: repository.document}, nil
}

// TakeRepositoryVersion replaces the site version of a post with its repository version. The uploaded images
// stay. The merge state then records the new site version as merged, so a later repository change applies again.
func (store *Store) TakeRepositoryVersion(slug string) error {
	if !validSlug(slug) {
		return ErrInvalidSlug
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	seed, err := store.readSeedVersion(slug)
	if err != nil {
		return err
	}
	// The post keeps its address: a slug renamed in the admin stays, the rest is the repository's.
	metadata := seed.document.Metadata
	metadataBytes := seed.metadata
	if metadata.Slug != slug {
		metadata.Slug = slug
		encoded, err := json.MarshalIndent(metadata, "", "  ")
		if err != nil {
			return fmt.Errorf("encode blog metadata: %w", err)
		}
		metadataBytes = append(encoded, '\n')
	}

	staging, err := os.MkdirTemp(store.root, stagingPrefix+"*")
	if err != nil {
		return fmt.Errorf("stage blog post: %w", err)
	}
	defer os.RemoveAll(staging)
	if err := copyAssets(filepath.Join(store.postDirectory(slug), "assets"), filepath.Join(staging, "assets")); err != nil {
		return fmt.Errorf("stage blog assets: %w", err)
	}
	if err := atomicWrite(filepath.Join(staging, "post.json"), metadataBytes, 0o644); err != nil {
		return fmt.Errorf("write blog metadata: %w", err)
	}
	if err := atomicWrite(filepath.Join(staging, "content.md"), seed.content, 0o644); err != nil {
		return fmt.Errorf("write blog markdown: %w", err)
	}
	if err := store.commitPostDirectory(staging, slug, slug); err != nil {
		return err
	}

	live, err := postHash(func(name string) ([]byte, error) { return os.ReadFile(filepath.Join(store.postDirectory(slug), name)) })
	if err != nil {
		return err
	}
	seedHash, err := postHash(func(name string) ([]byte, error) {
		if name == "post.json" {
			return seed.metadata, nil
		}
		return seed.content, nil
	})
	if err != nil {
		return err
	}
	state, err := readSeedState(store.root)
	if err != nil {
		return err
	}
	state[seed.key] = seedRecord{Seed: seedHash, Live: live}
	return writeSeedState(store.root, state)
}

// KeepSiteVersion drops the repository version of a post. The merge state is unchanged: the post stays out of
// the merges until the repository changes again, which reports a new conflict.
func (store *Store) KeepSiteVersion(slug string) error {
	if !validSlug(slug) {
		return ErrInvalidSlug
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	if _, err := store.readSeedVersion(slug); err != nil {
		return err
	}
	for _, name := range []string{seedMetadataName, seedContentName} {
		if err := os.Remove(filepath.Join(store.postDirectory(slug), name)); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove %s: %w", name, err)
		}
	}
	return nil
}

type seedVersion struct {
	document Document
	metadata []byte
	content  []byte
	// key is the entry of the post in the merge state: its ID, or its repository slug.
	key string
}

// readSeedVersion reads the repository version MergeSeed left next to a post. The caller holds the lock.
func (store *Store) readSeedVersion(slug string) (seedVersion, error) {
	directory := store.postDirectory(slug)
	metadataBytes, err := os.ReadFile(filepath.Join(directory, seedMetadataName))
	if errors.Is(err, os.ErrNotExist) {
		return seedVersion{}, ErrNoConflict
	}
	if err != nil {
		return seedVersion{}, err
	}
	content, err := os.ReadFile(filepath.Join(directory, seedContentName))
	if errors.Is(err, os.ErrNotExist) {
		return seedVersion{}, ErrNoConflict
	}
	if err != nil {
		return seedVersion{}, err
	}
	var metadata Metadata
	if err := json.Unmarshal(metadataBytes, &metadata); err != nil {
		return seedVersion{}, fmt.Errorf("decode %s: %w", seedMetadataName, err)
	}
	key := metadata.ID
	if key == "" {
		key = metadata.Slug
	}
	if key == "" {
		return seedVersion{}, fmt.Errorf("%s has neither an ID nor a slug", seedMetadataName)
	}
	return seedVersion{
		document: Document{Metadata: metadata, Markdown: NormalizeMarkdown(string(content))},
		metadata: metadataBytes, content: content, key: key,
	}, nil
}
