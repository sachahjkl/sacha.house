package blog

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"
	"time"
)

func savePost(t *testing.T, store *Store, slug string) {
	t.Helper()
	if _, err := store.Save(SaveInput{Title: "Post", Slug: slug, Language: "en", Markdown: "content of " + slug}, ""); err != nil {
		t.Fatal(err)
	}
}

// interruptRename leaves the store as a crash does when post "old" was being renamed to "new", with images
// already uploaded under "new": the old post is in a backup and "new" holds no post.
func interruptRename(t *testing.T, store *Store) {
	t.Helper()
	savePost(t, store, "old")
	if _, err := store.Upload("new", "image.png", "image/png", []byte("png")); err != nil {
		t.Fatal(err)
	}
	if err := writeCommitMarker(store.postDirectory("old"), "new"); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(store.postDirectory("old"), filepath.Join(store.root, backupPrefix+"old-x")); err != nil {
		t.Fatal(err)
	}
}

func TestRecoveryKeepsAPostWhoseTargetHoldsOnlyUploads(t *testing.T) {
	store := newTestStore(t)
	interruptRename(t, store)

	recovered, err := NewStore(store.root, "Author")
	if err != nil {
		t.Fatal(err)
	}
	document, err := recovered.Load("old", true)
	if err != nil || document.Markdown != "content of old" {
		t.Fatalf("the post was lost: %#v, %v", document, err)
	}
	if entries, _ := filepath.Glob(filepath.Join(store.root, backupPrefix+"*")); len(entries) != 0 {
		t.Fatalf("backups left behind: %v", entries)
	}
}

func TestRecoveryKeepsAPostWhenBothDirectoriesWereMoved(t *testing.T) {
	store := newTestStore(t)
	interruptRename(t, store)
	if err := writeCommitMarker(store.postDirectory("new"), "new"); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(store.postDirectory("new"), filepath.Join(store.root, backupPrefix+"new-x")); err != nil {
		t.Fatal(err)
	}

	recovered, err := NewStore(store.root, "Author")
	if err != nil {
		t.Fatal(err)
	}
	if document, err := recovered.Load("old", true); err != nil || document.Markdown != "content of old" {
		t.Fatalf("the post was lost: %#v, %v", document, err)
	}
	if matches, _ := filepath.Glob(filepath.Join(store.postDirectory("new"), "assets", "*.png")); len(matches) != 1 {
		t.Fatalf("the uploaded image was lost: %v", matches)
	}
}

func TestRecoveryDropsTheBackupOfAFinishedCommit(t *testing.T) {
	store := newTestStore(t)
	savePost(t, store, "target")
	backup := filepath.Join(store.root, backupPrefix+"old-x")
	if err := os.MkdirAll(backup, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(backup, commitMarker), []byte("target\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := NewStore(store.root, "Author"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(backup); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("the backup of a finished commit survived: %v", err)
	}
}

func TestRecoveryRunsBeforeTheSeedCanReplaceAnEditedPost(t *testing.T) {
	store := newTestStore(t)
	savePost(t, store, "kept")
	if err := writeCommitMarker(store.postDirectory("kept"), "kept"); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(store.postDirectory("kept"), filepath.Join(store.root, backupPrefix+"old-x")); err != nil {
		t.Fatal(err)
	}

	recovered, err := NewStore(store.root, "Author")
	if err != nil {
		t.Fatal(err)
	}
	seed := fstest.MapFS{}
	seedPost(seed, "kept", "Seed version")
	if imported, err := MergeSeed(store.root, seed); err != nil || len(imported.Imported) != 0 {
		t.Fatalf("imported = %v, %v", imported, err)
	}
	if document, err := recovered.Load("kept", true); err != nil || document.Markdown != "content of kept" {
		t.Fatalf("the edited post was replaced: %#v, %v", document, err)
	}
}

func TestRecoveryRemovesAbandonedImports(t *testing.T) {
	store := newTestStore(t)
	abandoned := filepath.Join(store.root, importPrefix+"x")
	if err := os.MkdirAll(abandoned, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := NewStore(store.root, "Author"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(abandoned); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("the abandoned import survived: %v", err)
	}
}

func TestImportDoesNotBringBackARenamedPost(t *testing.T) {
	store := newTestStore(t)
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")
	if _, err := MergeSeed(store.root, seed); err != nil {
		t.Fatal(err)
	}
	document, err := store.Load("first", true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Save(SaveInput{Title: "Renamed", Slug: "renamed", Language: "en", Markdown: document.Markdown}, "first"); err != nil {
		t.Fatal(err)
	}
	if imported, err := MergeSeed(store.root, seed); err != nil || len(imported.Imported) != 0 {
		t.Fatalf("the renamed post came back: %v, %v", imported, err)
	}
}

func TestImportFillsADirectoryHoldingOnlyUploads(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Upload("first", "image.png", "image/png", []byte("png")); err != nil {
		t.Fatal(err)
	}
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")
	if imported, err := MergeSeed(store.root, seed); err != nil || len(imported.Imported) != 1 {
		t.Fatalf("imported = %v, %v", imported, err)
	}
	if _, err := store.Load("first", true); err != nil {
		t.Fatal(err)
	}
	if matches, _ := filepath.Glob(filepath.Join(store.postDirectory("first"), "assets", "*.png")); len(matches) != 1 {
		t.Fatalf("the uploaded image was lost: %v", matches)
	}
}

func TestDiagramSyncKeepsEntriesTheDeployedPostStillUses(t *testing.T) {
	root := t.TempDir()
	directory := filepath.Join(root, "post", "assets", diagramDirectory)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "post", "content.md"), []byte("edited"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, diagramManifest), []byte(`{"aaaaaaaaaaaaaaaa":{"title":"old"}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	seed := fstest.MapFS{}
	seedPost(seed, "post", "Post")
	seed["post/assets/diagrams/index.json"] = &fstest.MapFile{Data: []byte(`{"bbbbbbbbbbbbbbbb":{"title":"new"}}`)}
	if _, err := MergeSeed(root, seed); err != nil {
		t.Fatal(err)
	}
	manifest, err := os.ReadFile(filepath.Join(directory, diagramManifest))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(manifest), "aaaaaaaaaaaaaaaa") || !strings.Contains(string(manifest), "bbbbbbbbbbbbbbbb") {
		t.Fatalf("manifest = %s", manifest)
	}
}

func TestSaveRefusesAStaleEditor(t *testing.T) {
	store := newTestStore(t)
	savePost(t, store, "post")
	document, err := store.Load("post", true)
	if err != nil {
		t.Fatal(err)
	}
	input := SaveInput{Title: "Post", Slug: "post", Language: "en", Markdown: "stale", Revision: "2000-01-01T00:00:00Z"}
	if _, err := store.Save(input, "post"); !errors.Is(err, ErrPostConflict) {
		t.Fatalf("Save() error = %v, want a conflict", err)
	}
	input.Revision = document.Metadata.UpdatedAt
	if _, err := store.Save(input, "post"); err != nil {
		t.Fatal(err)
	}
}

func TestSaveDoesNotRecreateAPostRenamedElsewhere(t *testing.T) {
	store := newTestStore(t)
	input := SaveInput{Title: "Post", Slug: "gone", Language: "en", Markdown: "text"}
	if _, err := store.Save(input, "gone"); !errors.Is(err, ErrPostGone) {
		t.Fatalf("Save() error = %v, want ErrPostGone", err)
	}
	if _, err := os.Stat(store.postDirectory("gone")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("the post was recreated: %v", err)
	}
}

func TestSaveRejectsTheReservedSlug(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Save(SaveInput{Title: "New", Slug: "new", Language: "en"}, ""); !errors.Is(err, ErrReservedSlug) {
		t.Fatalf("Save() error = %v", err)
	}
}

func TestFirstPublishUsesThePublicationDayNotTheDraftDay(t *testing.T) {
	store := newTestStore(t)
	savePost(t, store, "post")
	document, err := store.Load("post", true)
	if err != nil {
		t.Fatal(err)
	}
	later := store.now().AddDate(0, 3, 0)
	store.now = func() time.Time { return later }
	if _, err := store.Save(SaveInput{Title: "Post", Slug: "post", Language: "en", Status: "published", Markdown: "text"}, "post"); err != nil {
		t.Fatal(err)
	}
	published, err := store.Load("post", false)
	if err != nil {
		t.Fatal(err)
	}
	if published.Metadata.PublishedAt == document.Metadata.CreatedAt || !strings.HasPrefix(published.Metadata.PublishedAt, "2026-11-05") {
		t.Fatalf("PublishedAt = %q", published.Metadata.PublishedAt)
	}
}

func TestUploadForRefusesTheSlugOfAnotherPost(t *testing.T) {
	store := newTestStore(t)
	savePost(t, store, "other")
	if _, err := store.UploadFor("other", "", "image.png", "image/png", []byte("png")); !errors.Is(err, ErrPostExists) {
		t.Fatalf("UploadFor() error = %v", err)
	}
	if _, err := store.UploadFor("other", "other", "image.png", "image/png", []byte("png")); err != nil {
		t.Fatalf("the post's own upload failed: %v", err)
	}
	if _, err := store.UploadFor("free", "", "image.png", "image/png", []byte("png")); err != nil {
		t.Fatalf("a new post's upload failed: %v", err)
	}
}

func TestListIgnoresUploadsWithoutAPost(t *testing.T) {
	store := newTestStore(t)
	if _, err := store.Upload("draft", "image.png", "image/png", []byte("png")); err != nil {
		t.Fatal(err)
	}
	if posts, err := store.List(true); err != nil || len(posts) != 0 {
		t.Fatalf("List() = %v, %v", posts, err)
	}
}

func TestDraftAssetsAreOpenOnlyThroughOpenAsset(t *testing.T) {
	store := newTestStore(t)
	savePost(t, store, "draft")
	upload, err := store.Upload("draft", "image.png", "image/png", []byte("png"))
	if err != nil {
		t.Fatal(err)
	}
	name := filepath.Base(upload.URL)
	if _, err := store.OpenPublishedAsset("draft", name); !errors.Is(err, ErrNotPublished) {
		t.Fatalf("OpenPublishedAsset() error = %v", err)
	}
	file, err := store.OpenAsset("draft", name)
	if err != nil {
		t.Fatal(err)
	}
	_ = file.Close()
}
