package blog

import (
	"archive/zip"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
)

// WriteArchive writes the site version of a post as a zip: <slug>/post.json, <slug>/content.md and the uploaded
// images of <slug>/assets. Extracted in data/blog, it puts the post in the repository as the admin holds it. The
// prerendered diagrams are left out: `just diagrams` draws them from the text.
func (store *Store) WriteArchive(slug string, writer io.Writer) error {
	if !validSlug(slug) {
		return ErrInvalidSlug
	}
	store.mu.RLock()
	defer store.mu.RUnlock()
	directory := store.postDirectory(slug)
	if ok, err := hasPost(directory); err != nil {
		return err
	} else if !ok {
		return fs.ErrNotExist
	}

	archive := zip.NewWriter(writer)
	add := func(name, source string) error {
		file, err := os.Open(source)
		if err != nil {
			return err
		}
		defer file.Close()
		info, err := file.Stat()
		if err != nil {
			return err
		}
		header, err := zip.FileInfoHeader(info)
		if err != nil {
			return err
		}
		header.Name = path.Join(slug, name)
		header.Method = zip.Deflate
		entry, err := archive.CreateHeader(header)
		if err != nil {
			return err
		}
		_, err = io.Copy(entry, file)
		return err
	}
	for _, name := range []string{"post.json", "content.md"} {
		if err := add(name, filepath.Join(directory, name)); err != nil {
			return fmt.Errorf("archive %s: %w", name, err)
		}
	}
	assets := filepath.Join(directory, "assets")
	err := filepath.WalkDir(assets, func(name string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			if name == assets && os.IsNotExist(walkErr) {
				return fs.SkipDir
			}
			return walkErr
		}
		if entry.IsDir() {
			if entry.Name() == diagramDirectory && filepath.Dir(name) == assets {
				return fs.SkipDir
			}
			return nil
		}
		if !entry.Type().IsRegular() {
			return nil
		}
		relative, err := filepath.Rel(directory, name)
		if err != nil {
			return err
		}
		return add(filepath.ToSlash(relative), name)
	})
	if err != nil {
		return fmt.Errorf("archive assets: %w", err)
	}
	return archive.Close()
}
