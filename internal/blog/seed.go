package blog

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
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

// seedStateName is the file of the blog root that remembers, for each post of the repository, what the last merge saw.
// It lives outside the post directories because Store.Save rebuilds a post directory from scratch.
const seedStateName = ".seed-state.json"

// seedRecord is the memory of one post. Seed is the hash of the repository version that was last imported or
// reported. Live is the hash of the version the site held right after the last import: if the site still holds
// it, nobody edited the post in the admin since.
type seedRecord struct {
	Seed string `json:"seed"`
	Live string `json:"live"`
}

// SeedResult lists what MergeSeed did, by slug.
type SeedResult struct {
	Imported  []string // posts the site did not have: copied
	Updated   []string // posts that only the repository changed: replaced
	Conflicts []string // posts that both sides changed: the site version stays
}

// MergeSeed merges the posts of seed into root with a three-way merge, and reports what it did.
//
// seed holds one directory per post. For each post of the repository, the site version, the repository version,
// and the version of the last merge (the base) decide:
//   - The site has no post of that slug or of that ID: the post is imported. The ID survives a rename in the
//     admin, so a post renamed there does not come back under its old slug.
//   - The repository version is the one of the last merge, or the site already holds it: nothing to do.
//   - Only the repository changed since the last merge: the site post is replaced. Its uploaded images stay.
//   - Both sides changed, or the post was never merged before and differs: the site version stays. The
//     repository version is written next to it as post.seed.json and content.seed.md, and the post is listed in
//     Conflicts. It is reported once: it is reported again only when the repository changes again.
//
// A post is written to a temporary directory inside root, then moved into place, so a post that is visible is
// always complete. A post that cannot be merged does not stop the others. Run it after NewStore: recovery must
// see an interrupted commit before a merge can take its place.
func MergeSeed(root string, seed fs.FS) (SeedResult, error) {
	var result SeedResult
	entries, err := fs.ReadDir(seed, ".")
	if err != nil {
		return result, fmt.Errorf("read the blog seed: %w", err)
	}
	absoluteRoot, err := filepath.Abs(root)
	if err != nil {
		return result, err
	}
	if err := os.MkdirAll(absoluteRoot, 0o755); err != nil {
		return result, err
	}
	state, err := readSeedState(absoluteRoot)
	if err != nil {
		return result, err
	}

	owners := postOwners(absoluteRoot)
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
		id := seedPostID(seed, slug)
		key := id
		if key == "" {
			key = slug
		}
		destination := filepath.Join(absoluteRoot, slug)
		if owner, found := owners[id]; found {
			destination = filepath.Join(absoluteRoot, owner)
		}
		exists, err := hasPost(destination)
		if err != nil {
			failures = append(failures, fmt.Errorf("%s: %w", slug, err))
			continue
		}
		seedHash, err := postHash(func(name string) ([]byte, error) { return fs.ReadFile(seed, path.Join(slug, name)) })
		if err != nil {
			failures = append(failures, fmt.Errorf("%s: %w", slug, err))
			continue
		}
		if !exists {
			if err := copySeedPost(seed, slug, destination); err != nil {
				failures = append(failures, fmt.Errorf("%s: %w", slug, err))
				continue
			}
			state[key] = seedRecord{Seed: seedHash, Live: seedHash}
			result.Imported = append(result.Imported, slug)
			continue
		}

		record, known := state[key]
		// A post that lacks one of its files was edited by hand: its hash is empty and matches nothing.
		liveHash, _ := postHash(func(name string) ([]byte, error) { return os.ReadFile(filepath.Join(destination, name)) })
		switch {
		case known && record.Seed == seedHash:
		case liveHash == seedHash:
			state[key] = seedRecord{Seed: seedHash, Live: seedHash}
		case known && liveHash != "" && liveHash == record.Live:
			if err := copySeedPost(seed, slug, destination); err != nil {
				failures = append(failures, fmt.Errorf("%s: %w", slug, err))
				continue
			}
			state[key] = seedRecord{Seed: seedHash, Live: seedHash}
			result.Updated = append(result.Updated, slug)
		default:
			if err := writeSeedConflict(seed, slug, destination); err != nil {
				failures = append(failures, fmt.Errorf("%s conflict: %w", slug, err))
				continue
			}
			state[key] = seedRecord{Seed: seedHash, Live: record.Live}
			result.Conflicts = append(result.Conflicts, slug)
		}
		// Prerendered diagrams are build output, not text: keep them current whatever the merge decided.
		if err := syncSeedDiagrams(seed, slug, destination); err != nil {
			failures = append(failures, fmt.Errorf("%s diagrams: %w", slug, err))
		}
	}
	if err := writeSeedState(absoluteRoot, state); err != nil {
		failures = append(failures, err)
	}
	sort.Strings(result.Imported)
	sort.Strings(result.Updated)
	sort.Strings(result.Conflicts)
	return result, errors.Join(failures...)
}

// postHash hashes the two text files of a post. Images and diagrams are not part of the merge.
func postHash(read func(name string) ([]byte, error)) (string, error) {
	hash := sha256.New()
	for _, name := range []string{"post.json", "content.md"} {
		content, err := read(name)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(hash, "%s %d\n", name, len(content))
		hash.Write(content)
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func writeSeedConflict(seed fs.FS, slug, destination string) error {
	for source, target := range map[string]string{"post.json": "post.seed.json", "content.md": "content.seed.md"} {
		content, err := fs.ReadFile(seed, path.Join(slug, source))
		if err != nil {
			return err
		}
		if err := writeIfChanged(filepath.Join(destination, target), content); err != nil {
			return err
		}
	}
	return nil
}

func readSeedState(root string) (map[string]seedRecord, error) {
	state := map[string]seedRecord{}
	content, err := os.ReadFile(filepath.Join(root, seedStateName))
	if errors.Is(err, fs.ErrNotExist) {
		return state, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", seedStateName, err)
	}
	if err := json.Unmarshal(content, &state); err != nil {
		return nil, fmt.Errorf("decode %s: %w", seedStateName, err)
	}
	return state, nil
}

func writeSeedState(root string, state map[string]seedRecord) error {
	content, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("encode %s: %w", seedStateName, err)
	}
	if err := writeIfChanged(filepath.Join(root, seedStateName), append(content, '\n')); err != nil {
		return fmt.Errorf("write %s: %w", seedStateName, err)
	}
	return nil
}

// postOwners maps the ID of every post of root to its directory: the ID survives a rename, the slug does not.
func postOwners(root string) map[string]string {
	owners := make(map[string]string)
	entries, err := os.ReadDir(root)
	if err != nil {
		return owners
	}
	for _, entry := range entries {
		if !entry.IsDir() || !validSlug(entry.Name()) {
			continue
		}
		content, err := os.ReadFile(filepath.Join(root, entry.Name(), "post.json"))
		if err != nil {
			continue
		}
		var metadata Metadata
		if json.Unmarshal(content, &metadata) == nil && metadata.ID != "" {
			owners[metadata.ID] = entry.Name()
		}
	}
	return owners
}

func seedPostID(seed fs.FS, slug string) string {
	content, err := fs.ReadFile(seed, path.Join(slug, "post.json"))
	if err != nil {
		return ""
	}
	var metadata Metadata
	if json.Unmarshal(content, &metadata) != nil {
		return ""
	}
	return metadata.ID
}

// hasPost reports whether directory holds a post. Images uploaded for a post that was never saved do not count.
func hasPost(directory string) (bool, error) {
	for _, name := range []string{"post.json", "content.md"} {
		if _, err := os.Lstat(filepath.Join(directory, name)); err == nil {
			return true, nil
		} else if !errors.Is(err, fs.ErrNotExist) {
			return false, err
		}
	}
	return false, nil
}

func copySeedPost(seed fs.FS, slug, destination string) error {
	staging, err := os.MkdirTemp(filepath.Dir(destination), importPrefix)
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
	if _, err := os.Stat(destination); err == nil {
		// Only images can be here: keep them with the post.
		if err := copyAssets(filepath.Join(destination, "assets"), filepath.Join(staging, "assets")); err != nil {
			return err
		}
		if err := os.RemoveAll(destination); err != nil {
			return err
		}
	}
	return os.Rename(staging, destination)
}

// syncSeedDiagrams copies the prerendered diagrams of a seed post (assets/diagrams) into a post that already
// exists. They are generated by tools/diagrams.ts from the post's Markdown and named after the hash of each
// block, so overwriting them never loses an edit: a block the admin changed simply finds no drawing and shows
// its source. The manifest is written last, so a diagram is never listed before its files exist, and it keeps
// the entries it already had: the Markdown of the post may still use a block the repository has since changed.
func syncSeedDiagrams(seed fs.FS, slug, destination string) error {
	directory := path.Join(slug, "assets", diagramDirectory)
	entries, err := fs.ReadDir(seed, directory)
	if err != nil {
		return nil
	}
	target := filepath.Join(destination, "assets", diagramDirectory)
	var manifest []byte
	for _, entry := range entries {
		if entry.IsDir() || !entry.Type().IsRegular() {
			continue
		}
		content, err := fs.ReadFile(seed, path.Join(directory, entry.Name()))
		if err != nil {
			return err
		}
		if entry.Name() == diagramManifest {
			manifest = content
			continue
		}
		if err := writeIfChanged(filepath.Join(target, entry.Name()), content); err != nil {
			return err
		}
	}
	if manifest != nil {
		return writeIfChanged(filepath.Join(target, diagramManifest), mergeManifests(filepath.Join(target, diagramManifest), manifest))
	}
	return nil
}

// mergeManifests adds the entries of the manifest at name to incoming, whose entries win.
func mergeManifests(name string, incoming []byte) []byte {
	current, err := os.ReadFile(name)
	if err != nil {
		return incoming
	}
	var merged, added map[string]json.RawMessage
	if json.Unmarshal(current, &merged) != nil || json.Unmarshal(incoming, &added) != nil {
		return incoming
	}
	for hash, entry := range added {
		merged[hash] = entry
	}
	encoded, err := json.MarshalIndent(merged, "", "  ")
	if err != nil {
		return incoming
	}
	return append(encoded, '\n')
}

func writeIfChanged(name string, content []byte) error {
	if existing, err := os.ReadFile(name); err == nil && string(existing) == string(content) {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(name), 0o755); err != nil {
		return err
	}
	temporary := name + ".tmp"
	if err := os.WriteFile(temporary, content, 0o644); err != nil {
		return err
	}
	return os.Rename(temporary, name)
}
