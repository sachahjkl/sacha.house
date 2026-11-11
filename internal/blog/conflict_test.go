package blog

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"testing/fstest"
)

// conflictedStore returns a store whose post "first" was edited in the admin and changed in the repository.
func conflictedStore(t *testing.T) (*Store, fstest.MapFS) {
	t.Helper()
	store := newTestStore(t)
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")
	if _, err := MergeSeed(store.root, seed); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Upload("first", "image.png", "image/png", []byte("png")); err != nil {
		t.Fatal(err)
	}
	save := SaveInput{Title: "First", Slug: "first", Language: "en", Status: "published", Markdown: "edited in the admin"}
	if _, err := store.Save(save, "first"); err != nil {
		t.Fatal(err)
	}
	changeSeed(seed, "first", "# Changed in the repository\n")
	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Conflicts) != 1 {
		t.Fatalf("merge = %#v, %v; want a conflict", result, err)
	}
	return store, seed
}

func seedFilesLeft(store *Store, slug string) bool {
	for _, name := range []string{seedMetadataName, seedContentName} {
		if _, err := os.Stat(filepath.Join(store.postDirectory(slug), name)); err == nil {
			return true
		}
	}
	return false
}

func TestConflictShowsBothVersions(t *testing.T) {
	store, _ := conflictedStore(t)
	if !store.HasConflict("first") {
		t.Fatal("HasConflict() = false")
	}
	conflict, err := store.Conflict("first")
	if err != nil {
		t.Fatal(err)
	}
	if conflict.Site.Markdown != "edited in the admin" || conflict.Repository.Markdown != "# Changed in the repository\n" {
		t.Fatalf("conflict = %#v", conflict)
	}
	if _, err := store.Conflict("missing"); err == nil {
		t.Fatal("a missing post has no conflict")
	}
}

func TestTakeRepositoryVersionReplacesThePostAndMergesLater(t *testing.T) {
	store, seed := conflictedStore(t)
	if err := store.TakeRepositoryVersion("first"); err != nil {
		t.Fatal(err)
	}
	if got := readPost(t, store, "first"); got != "# Changed in the repository" {
		t.Fatalf("markdown = %q", got)
	}
	if seedFilesLeft(store, "first") || store.HasConflict("first") {
		t.Fatal("the repository version is still waiting")
	}
	if matches, _ := filepath.Glob(filepath.Join(store.postDirectory("first"), "assets", "*.png")); len(matches) != 1 {
		t.Fatalf("the uploaded image was lost: %v", matches)
	}
	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Updated)+len(result.Conflicts) != 0 {
		t.Fatalf("merge after the resolution = %#v, %v; want nothing", result, err)
	}
	// The resolution counts as a merge: the next repository change applies without a conflict.
	changeSeed(seed, "first", "# Changed again\n")
	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Updated) != 1 || len(result.Conflicts) != 0 {
		t.Fatalf("merge of a new repository change = %#v, %v; want an update", result, err)
	}
	if got := readPost(t, store, "first"); got != "# Changed again" {
		t.Fatalf("markdown = %q", got)
	}
}

func TestKeepSiteVersionDropsTheRepositoryVersion(t *testing.T) {
	store, seed := conflictedStore(t)
	if err := store.KeepSiteVersion("first"); err != nil {
		t.Fatal(err)
	}
	if got := readPost(t, store, "first"); got != "edited in the admin" {
		t.Fatalf("markdown = %q", got)
	}
	if seedFilesLeft(store, "first") {
		t.Fatal("the repository version is still on disk")
	}
	if err := store.KeepSiteVersion("first"); !errors.Is(err, ErrNoConflict) {
		t.Fatalf("second resolution error = %v, want ErrNoConflict", err)
	}
	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Conflicts) != 0 {
		t.Fatalf("merge after the resolution = %#v, %v; want nothing", result, err)
	}
	// The repository is still behind the site: its next change conflicts again instead of erasing the admin edit.
	changeSeed(seed, "first", "# Changed again\n")
	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Conflicts) != 1 {
		t.Fatalf("merge of a new repository change = %#v, %v; want a conflict", result, err)
	}
	if got := readPost(t, store, "first"); got != "edited in the admin" {
		t.Fatalf("the admin version was replaced: %q", got)
	}
}

func TestTakeRepositoryVersionKeepsARenamedSlug(t *testing.T) {
	store, _ := conflictedStore(t)
	save := SaveInput{Title: "First", Slug: "renamed", Language: "en", Status: "published", Markdown: "renamed in the admin"}
	if _, err := store.Save(save, "first"); err != nil {
		t.Fatal(err)
	}
	// Save rebuilds the directory: put the repository version back, as a merge after the rename would.
	for name, content := range map[string]string{
		seedMetadataName: `{"id":"first","slug":"first","title":"First","status":"published","language":"en"}`,
		seedContentName:  "# From the repository\n",
	} {
		if err := os.WriteFile(filepath.Join(store.postDirectory("renamed"), name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := store.TakeRepositoryVersion("renamed"); err != nil {
		t.Fatal(err)
	}
	document, err := store.Load("renamed", true)
	if err != nil {
		t.Fatal(err)
	}
	if document.Metadata.Slug != "renamed" || document.Markdown != "# From the repository\n" {
		t.Fatalf("document = %#v", document)
	}
}
