package blog

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"testing/fstest"
)

func seedPost(files fstest.MapFS, slug, title string) {
	files[slug+"/post.json"] = &fstest.MapFile{Data: []byte(`{"id":"` + slug + `","slug":"` + slug + `","title":"` + title + `","status":"published","language":"en"}`)}
	files[slug+"/content.md"] = &fstest.MapFile{Data: []byte("# " + title + "\n")}
}

func TestMergeSeedCopiesOnlyAbsentPosts(t *testing.T) {
	root := filepath.Join(t.TempDir(), "data", "blog")
	if err := os.MkdirAll(filepath.Join(root, "kept"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "kept", "content.md"), []byte("edited in the admin"), 0o644); err != nil {
		t.Fatal(err)
	}

	seed := fstest.MapFS{}
	seedPost(seed, "kept", "Kept")
	seedPost(seed, "new-post", "New")
	seed["new-post/assets/image.png"] = &fstest.MapFile{Data: []byte("png")}
	seed["incomplete/post.json"] = &fstest.MapFile{Data: []byte("{}")}
	seed["Not_A_Slug/post.json"] = &fstest.MapFile{Data: []byte("{}")}
	seed["loose-file.txt"] = &fstest.MapFile{Data: []byte("x")}

	imported, err := MergeSeed(root, seed)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"new-post"}; !reflect.DeepEqual(imported.Imported, want) {
		t.Fatalf("imported = %v, want %v", imported, want)
	}

	if got, _ := os.ReadFile(filepath.Join(root, "kept", "content.md")); string(got) != "edited in the admin" {
		t.Fatalf("an existing post was overwritten: %q", got)
	}
	if got, err := os.ReadFile(filepath.Join(root, "new-post", "assets", "image.png")); err != nil || string(got) != "png" {
		t.Fatalf("the asset was not copied: %q, %v", got, err)
	}
	for _, name := range []string{"incomplete", "Not_A_Slug", "loose-file.txt"} {
		if _, err := os.Stat(filepath.Join(root, name)); err == nil {
			t.Errorf("%s should not have been imported", name)
		}
	}
	leftovers, _ := filepath.Glob(filepath.Join(root, ".import-*"))
	if len(leftovers) != 0 {
		t.Fatalf("temporary directories left behind: %v", leftovers)
	}

	store, err := NewStore(root, "Author")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Load("new-post", false); err != nil {
		t.Fatalf("the imported post cannot be loaded: %v", err)
	}
}

func TestMergeSeedIsIdempotentAndRespectsDeletions(t *testing.T) {
	root := filepath.Join(t.TempDir(), "blog")
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")

	if imported, err := MergeSeed(root, seed); err != nil || len(imported.Imported) != 1 {
		t.Fatalf("first import = %v, %v", imported, err)
	}
	if imported, err := MergeSeed(root, seed); err != nil || len(imported.Imported) != 0 {
		t.Fatalf("second import = %v, %v; want nothing", imported, err)
	}
}

func TestImportSyncsDiagramsOfExistingPosts(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "old"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "old", "content.md"), []byte("edited"), 0o644); err != nil {
		t.Fatal(err)
	}
	seed := fstest.MapFS{}
	seedPost(seed, "old", "Old")
	seed["old/assets/diagrams/index.json"] = &fstest.MapFile{Data: []byte("{}")}
	seed["old/assets/diagrams/0123456789abcdef-light.svg"] = &fstest.MapFile{Data: []byte("<svg/>")}
	for range 2 {
		if _, err := MergeSeed(root, seed); err != nil {
			t.Fatal(err)
		}
	}
	if got, _ := os.ReadFile(filepath.Join(root, "old", "content.md")); string(got) != "edited" {
		t.Fatalf("an existing post was overwritten: %q", got)
	}
	if got, err := os.ReadFile(filepath.Join(root, "old", "assets", "diagrams", "0123456789abcdef-light.svg")); err != nil || string(got) != "<svg/>" {
		t.Fatalf("the diagrams were not synced: %q, %v", got, err)
	}
}

func changeSeed(seed fstest.MapFS, slug, markdown string) {
	seed[slug+"/content.md"] = &fstest.MapFile{Data: []byte(markdown)}
}

func readPost(t *testing.T, store *Store, slug string) string {
	t.Helper()
	document, err := store.Load(slug, true)
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(document.Markdown)
}

func TestMergeSeedUpdatesAPostOnlyTheRepositoryChanged(t *testing.T) {
	store := newTestStore(t)
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")
	if _, err := MergeSeed(store.root, seed); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Upload("first", "image.png", "image/png", []byte("png")); err != nil {
		t.Fatal(err)
	}

	changeSeed(seed, "first", "# First, corrected\n")
	result, err := MergeSeed(store.root, seed)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(result.Updated, []string{"first"}) || len(result.Conflicts) != 0 {
		t.Fatalf("result = %#v", result)
	}
	if got := readPost(t, store, "first"); got != "# First, corrected" {
		t.Fatalf("markdown = %q", got)
	}
	if matches, _ := filepath.Glob(filepath.Join(store.postDirectory("first"), "assets", "*.png")); len(matches) != 1 {
		t.Fatalf("the uploaded image was lost: %v", matches)
	}

	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Updated)+len(result.Conflicts)+len(result.Imported) != 0 {
		t.Fatalf("second merge = %#v, %v; want nothing", result, err)
	}
}

func TestMergeSeedKeepsTheAdminVersionOnConflictAndReportsItOnce(t *testing.T) {
	store := newTestStore(t)
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")
	if _, err := MergeSeed(store.root, seed); err != nil {
		t.Fatal(err)
	}
	save := SaveInput{Title: "First", Slug: "first", Language: "en", Status: "published", Markdown: "edited in the admin"}
	if _, err := store.Save(save, "first"); err != nil {
		t.Fatal(err)
	}

	changeSeed(seed, "first", "# Changed in the repository\n")
	result, err := MergeSeed(store.root, seed)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(result.Conflicts, []string{"first"}) || len(result.Updated) != 0 {
		t.Fatalf("result = %#v", result)
	}
	if got := readPost(t, store, "first"); got != "edited in the admin" {
		t.Fatalf("the admin version was replaced: %q", got)
	}
	if got, _ := os.ReadFile(filepath.Join(store.postDirectory("first"), "content.seed.md")); string(got) != "# Changed in the repository\n" {
		t.Fatalf("content.seed.md = %q", got)
	}
	if _, err := os.Stat(filepath.Join(store.postDirectory("first"), "post.seed.json")); err != nil {
		t.Fatalf("post.seed.json is missing: %v", err)
	}

	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Conflicts) != 0 {
		t.Fatalf("the conflict was reported twice: %#v, %v", result, err)
	}
	changeSeed(seed, "first", "# Changed again\n")
	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Conflicts) != 1 {
		t.Fatalf("a new repository change must conflict again: %#v, %v", result, err)
	}
	if got := readPost(t, store, "first"); got != "edited in the admin" {
		t.Fatalf("the admin version was replaced: %q", got)
	}
}

func TestMergeSeedAdoptsAnExistingPostThatMatchesTheRepository(t *testing.T) {
	store := newTestStore(t)
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")
	if err := copySeedPost(seed, "first", store.postDirectory("first")); err != nil {
		t.Fatal(err)
	}

	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Conflicts) != 0 || len(result.Updated) != 0 {
		t.Fatalf("result = %#v, %v", result, err)
	}
	changeSeed(seed, "first", "# First, corrected\n")
	if result, err := MergeSeed(store.root, seed); err != nil || len(result.Updated) != 1 {
		t.Fatalf("result = %#v, %v; want an update", result, err)
	}
}

func TestMergeSeedReportsAnExistingPostThatDiffersAndHasNoMemory(t *testing.T) {
	store := newTestStore(t)
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")
	if err := copySeedPost(seed, "first", store.postDirectory("first")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(store.postDirectory("first"), "content.md"), []byte("edited before the merge existed"), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := MergeSeed(store.root, seed)
	if err != nil || len(result.Conflicts) != 1 {
		t.Fatalf("result = %#v, %v", result, err)
	}
	if got := readPost(t, store, "first"); got != "edited before the merge existed" {
		t.Fatalf("the site version was replaced: %q", got)
	}
}

func TestMergeSeedRejectsACorruptState(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, seedStateName), []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")
	if _, err := MergeSeed(root, seed); err == nil {
		t.Fatal("a corrupt state must stop the merge")
	}
	if _, err := os.Stat(filepath.Join(root, "first")); err == nil {
		t.Fatal("nothing must be written when the state is corrupt")
	}
}
