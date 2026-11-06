package blog

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"testing/fstest"
)

func seedPost(files fstest.MapFS, slug, title string) {
	files[slug+"/post.json"] = &fstest.MapFile{Data: []byte(`{"id":"` + slug + `","slug":"` + slug + `","title":"` + title + `","status":"published","language":"en"}`)}
	files[slug+"/content.md"] = &fstest.MapFile{Data: []byte("# " + title + "\n")}
}

func TestImportMissingCopiesOnlyAbsentPosts(t *testing.T) {
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

	imported, err := ImportMissing(root, seed)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"new-post"}; !reflect.DeepEqual(imported, want) {
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
	leftovers, _ := filepath.Glob(filepath.Join(filepath.Dir(root), ".import-*"))
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

func TestImportMissingIsIdempotentAndRespectsDeletions(t *testing.T) {
	root := filepath.Join(t.TempDir(), "blog")
	seed := fstest.MapFS{}
	seedPost(seed, "first", "First")

	if imported, err := ImportMissing(root, seed); err != nil || len(imported) != 1 {
		t.Fatalf("first import = %v, %v", imported, err)
	}
	if imported, err := ImportMissing(root, seed); err != nil || len(imported) != 0 {
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
		if _, err := ImportMissing(root, seed); err != nil {
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
