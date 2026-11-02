package blog

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
)

var seedSlug = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)

// ImportMissing copies into root every post of seed that root does not have yet, and returns their slugs.
//
// seed holds one directory per post. A post is imported only when its directory is absent from root: an
// existing post is never touched, so edits made in the admin are never overwritten, and importing again does
// nothing. A post is copied to a temporary directory next to root, then moved into place, so a post that is
// visible is always complete. A post that cannot be imported does not stop the others.
func ImportMissing(root string, seed fs.FS) ([]string, error) {
	entries, err := fs.ReadDir(seed, ".")
	if err != nil {
		return nil, fmt.Errorf("read the blog seed: %w", err)
	}
	absoluteRoot, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(absoluteRoot, 0o755); err != nil {
		return nil, err
	}

	var imported []string
	var failures []error
	for _, entry := range entries {
		slug := entry.Name()
		if !entry.IsDir() || !seedSlug.MatchString(slug) {
			continue
		}
		if _, err := fs.Stat(seed, path.Join(slug, "post.json")); err != nil {
			continue
		}
		if _, err := fs.Stat(seed, path.Join(slug, "content.md")); err != nil {
			continue
		}
		destination := filepath.Join(absoluteRoot, slug)
		if _, err := os.Lstat(destination); err == nil {
			continue
		} else if !errors.Is(err, fs.ErrNotExist) {
			failures = append(failures, fmt.Errorf("%s: %w", slug, err))
			continue
		}
		if err := copySeedPost(seed, slug, destination); err != nil {
			failures = append(failures, fmt.Errorf("%s: %w", slug, err))
			continue
		}
		imported = append(imported, slug)
	}
	sort.Strings(imported)
	return imported, errors.Join(failures...)
}

func copySeedPost(seed fs.FS, slug, destination string) error {
	staging, err := os.MkdirTemp(filepath.Dir(destination), ".import-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(staging)

	err = fs.WalkDir(seed, slug, func(name string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative := name[len(slug):]
		target := filepath.Join(staging, filepath.FromSlash(relative))
		if entry.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		if !entry.Type().IsRegular() {
			return nil
		}
		content, err := fs.ReadFile(seed, name)
		if err != nil {
			return err
		}
		return os.WriteFile(target, content, 0o644)
	})
	if err != nil {
		return err
	}
	if err := os.Chmod(staging, 0o755); err != nil {
		return err
	}
	return os.Rename(staging, destination)
}
