package blog

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func newTestStore(t *testing.T) *Store {
	t.Helper()
	store, err := NewStore(filepath.Join(t.TempDir(), "blog"), "Sacha FROMENT")
	if err != nil {
		t.Fatal(err)
	}
	store.now = func() time.Time { return time.Date(2026, 8, 5, 12, 0, 0, 0, time.UTC) }
	return store
}

func TestSaveLoadListAndJSONFormat(t *testing.T) {
	store := newTestStore(t)
	slug, err := store.Save(SaveInput{
		Title: " First post ", Slug: "First Post", Status: "published",
		Language: "fr", PublishedAt: "2026-08-05T14:00", Markdown: "hello\r\nworld",
	}, "")
	if err != nil || slug != "first-post" {
		t.Fatalf("Save() = %q, %v", slug, err)
	}
	document, err := store.Load(slug, false)
	if err != nil {
		t.Fatal(err)
	}
	if document.Markdown != "hello\nworld" || document.Metadata.PublishedAt != "2026-08-05T12:00:00Z" {
		t.Fatalf("document = %#v", document)
	}
	if document.Metadata.ID != slug || document.Metadata.Author != "Sacha FROMENT" || document.Metadata.Language != "fr" || document.Metadata.Status != "published" {
		t.Fatalf("metadata = %#v", document.Metadata)
	}
	raw, err := os.ReadFile(store.metadataPath(slug))
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"id", "slug", "title", "language", "status", "publishedAt", "updatedAt", "createdAt", "author"} {
		if _, found := fields[field]; !found {
			t.Errorf("post.json lacks %q", field)
		}
	}
	posts, err := store.List(false)
	if err != nil || len(posts) != 1 || posts[0].Slug != slug {
		t.Fatalf("List() = %#v, %v", posts, err)
	}
}

func TestDraftFilteringDefaultsAndSorting(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Save(SaveInput{Title: "Old", Slug: "old", Language: "en", Status: "anything", Markdown: "old"}, ""); err != nil {
		t.Fatal(err)
	}
	store.now = func() time.Time { return time.Date(2026, 8, 6, 12, 0, 0, 0, time.UTC) }
	if _, err := store.Save(SaveInput{Title: "New", Slug: "new", Language: "en", Status: "published", Markdown: "new"}, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Load("old", false); !errors.Is(err, ErrNotPublished) {
		t.Fatalf("Load(draft) error = %v", err)
	}
	posts, err := store.List(true)
	if err != nil || len(posts) != 2 || posts[0].Slug != "new" || posts[1].Status != "draft" {
		t.Fatalf("List(true) = %#v, %v", posts, err)
	}
}

func TestRenamePreservesIdentityAndAssets(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Save(SaveInput{Title: "Post", Slug: "old", Language: "fr", Status: "published", Markdown: "![](/media/blog/old/assets/a.png)"}, ""); err != nil {
		t.Fatal(err)
	}
	assetDirectory := filepath.Join(store.postDirectory("old"), "assets")
	if err := os.MkdirAll(assetDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(assetDirectory, "a.png"), []byte("png"), 0o644); err != nil {
		t.Fatal(err)
	}
	created := store.now().UTC().Format(time.RFC3339)
	store.now = func() time.Time { return time.Date(2026, 8, 7, 12, 0, 0, 0, time.UTC) }
	slug, err := store.Save(SaveInput{Title: "Post", Slug: "new", Language: "fr", Status: "published", Markdown: "![](/media/blog/old/assets/a.png)"}, "old")
	if err != nil || slug != "new" {
		t.Fatalf("Save(rename) = %q, %v", slug, err)
	}
	document, err := store.Load("new", false)
	if err != nil {
		t.Fatal(err)
	}
	if document.Metadata.ID != "old" || document.Metadata.CreatedAt != created || document.Metadata.Language != "fr" {
		t.Fatalf("renamed metadata = %#v", document.Metadata)
	}
	if !strings.Contains(document.Markdown, "/media/blog/new/assets/") {
		t.Fatalf("renamed markdown = %q", document.Markdown)
	}
	if _, err := os.Stat(filepath.Join(store.postDirectory("new"), "assets", "a.png")); err != nil {
		t.Fatal(err)
	}
}

func TestSaveValidationAndCollision(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Save(SaveInput{Slug: "post", Language: "en"}, ""); err == nil {
		t.Fatal("Save() accepted an empty title")
	}
	if _, err := store.Save(SaveInput{Title: "Post", Slug: "post", Language: "en", PublishedAt: "bad"}, ""); err == nil {
		t.Fatal("Save() accepted an invalid date")
	}
	if _, err := store.Save(SaveInput{Title: "Post", Slug: "post", Language: "en"}, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Save(SaveInput{Title: "Duplicate", Slug: "post", Language: "en"}, ""); !errors.Is(err, ErrPostExists) {
		t.Fatalf("collision error = %v", err)
	}
	for _, slug := range []string{"../post", "/post", "post/name", "Post", "post_"} {
		if _, err := store.Load(slug, true); !errors.Is(err, ErrInvalidSlug) {
			t.Errorf("Load(%q) error = %v", slug, err)
		}
	}
}

func TestLoadRejectsMissingAndInvalidLanguage(t *testing.T) {
	store := newTestStore(t)
	directory := store.postDirectory("legacy")
	if err := os.MkdirAll(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	legacy := `{"id":"legacy","slug":"legacy","title":"Legacy","status":"draft"}`
	if err := os.WriteFile(store.metadataPath("legacy"), []byte(legacy), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(store.contentPath("legacy"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Load("legacy", true); err == nil {
		t.Fatal("Load() accepted missing language")
	}

	if _, err := store.Save(SaveInput{Title: "Post", Slug: "post", Language: "de"}, ""); err == nil {
		t.Fatal("Save() accepted an invalid language")
	}
	invalid := `{"id":"legacy","slug":"legacy","title":"Legacy","language":"de","status":"draft"}`
	if err := os.WriteFile(store.metadataPath("legacy"), []byte(invalid), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Load("legacy", true); err == nil {
		t.Fatal("Load() accepted an invalid language")
	}
}

func TestUpload(t *testing.T) {
	store := newTestStore(t)
	result, err := store.Upload("my-post", "My Picture", "image/png", []byte("image data"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(result.URL, "/media/blog/my-post/assets/my-picture-") || !strings.HasSuffix(result.URL, ".png") {
		t.Fatalf("Upload() URL = %q", result.URL)
	}
	if result.Markdown != "![my-picture]("+result.URL+")" {
		t.Fatalf("Upload() Markdown = %q", result.Markdown)
	}
	asset := filepath.Join(store.postDirectory("my-post"), strings.TrimPrefix(result.URL, MediaURLPrefix+"/my-post/"))
	content, err := os.ReadFile(asset)
	if err != nil || string(content) != "image data" {
		t.Fatalf("asset = %q, %v", content, err)
	}
	if _, err := store.Upload("../escape", "a.png", "image/png", nil); !errors.Is(err, ErrInvalidSlug) {
		t.Fatalf("unsafe slug error = %v", err)
	}
	if _, err := store.Upload("post", "image", "text/plain", nil); err == nil {
		t.Fatal("Upload() accepted an unsupported type")
	}
}

func TestOpenPublishedAsset(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Save(SaveInput{Title: "Post", Slug: "post", Language: "en", Status: "published"}, ""); err != nil {
		t.Fatal(err)
	}
	assetDirectory := filepath.Join(store.postDirectory("post"), "assets")
	if err := os.MkdirAll(assetDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(assetDirectory, "image.txt"), []byte("asset"), 0o644); err != nil {
		t.Fatal(err)
	}

	file, err := store.OpenPublishedAsset("post", "image.txt")
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	content, err := io.ReadAll(file)
	if err != nil || string(content) != "asset" {
		t.Fatalf("asset = %q, %v", content, err)
	}
}

func TestOpenPublishedAssetRejectsTraversal(t *testing.T) {
	store := newTestStore(t)
	tests := []struct {
		slug      string
		assetPath string
		want      error
	}{
		{slug: "../post", assetPath: "image.png", want: ErrInvalidSlug},
		{slug: "post", assetPath: "../post.json", want: ErrInvalidAsset},
	}
	for _, test := range tests {
		if _, err := store.OpenPublishedAsset(test.slug, test.assetPath); !errors.Is(err, test.want) {
			t.Errorf("OpenPublishedAsset(%q, %q) error = %v", test.slug, test.assetPath, err)
		}
	}
}

func TestOpenPublishedAssetRejectsMissingAsset(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Save(SaveInput{Title: "Post", Slug: "post", Language: "en", Status: "published"}, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := store.OpenPublishedAsset("post", "missing.png"); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("missing asset error = %v", err)
	}
}

func TestOpenPublishedAssetRejectsDraft(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Save(SaveInput{Title: "Post", Slug: "post", Language: "en", Status: "draft"}, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := store.OpenPublishedAsset("post", "image.png"); !errors.Is(err, ErrNotPublished) {
		t.Fatalf("draft asset error = %v", err)
	}
}

func TestSavePreservesAssetsUploadedBeforeNewPost(t *testing.T) {
	store := newTestStore(t)
	upload, err := store.Upload("future-post", "image", "image/png", []byte("image data"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Save(SaveInput{
		Title: "Future post", Slug: "future-post", Language: "en", Markdown: upload.Markdown,
	}, ""); err != nil {
		t.Fatal(err)
	}
	assetPath := strings.TrimPrefix(upload.URL, MediaURLPrefix+"/future-post/")
	content, err := os.ReadFile(filepath.Join(store.postDirectory("future-post"), filepath.FromSlash(assetPath)))
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "image data" {
		t.Fatalf("saved asset = %q", content)
	}
}

func TestNewStoreRecoversInterruptedDirectoryCommit(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Save(SaveInput{Title: "Post", Slug: "old", Language: "en", Markdown: "content"}, ""); err != nil {
		t.Fatal(err)
	}
	oldDirectory := store.postDirectory("old")
	if err := writeCommitMarker(oldDirectory, "new"); err != nil {
		t.Fatal(err)
	}
	backupDirectory := filepath.Join(store.root, backupPrefix+"old-interrupted")
	if err := os.Rename(oldDirectory, backupDirectory); err != nil {
		t.Fatal(err)
	}
	recovered, err := NewStore(store.root, "Sacha FROMENT")
	if err != nil {
		t.Fatal(err)
	}
	document, err := recovered.Load("old", true)
	if err != nil || document.Markdown != "content" {
		t.Fatalf("recovered document = %#v, %v", document, err)
	}
}

func TestConcurrentSaveAndLoad(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Save(SaveInput{Title: "Post", Slug: "post", Language: "en", Markdown: "initial"}, ""); err != nil {
		t.Fatal(err)
	}
	var wait sync.WaitGroup
	for i := 0; i < 10; i++ {
		wait.Add(2)
		go func() {
			defer wait.Done()
			_, _ = store.Save(SaveInput{Title: "Post", Slug: "post", Language: "en", Markdown: strings.Repeat("x", 100)}, "post")
		}()
		go func() {
			defer wait.Done()
			_, _ = store.Load("post", true)
		}()
	}
	wait.Wait()
	document, err := store.Load("post", true)
	if err != nil || len(document.Markdown) != 100 {
		t.Fatalf("final document length = %d, %v", len(document.Markdown), err)
	}
}
