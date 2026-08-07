package projects

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestClientFetchesMetadataCommitsAndSortsProjects(t *testing.T) {
	t.Helper()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("method = %s, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer token" {
			t.Errorf("Authorization = %q", got)
		}
		var request graphQLRequest
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatal(err)
		}
		if request.Variables["username"] != "sacha" {
			t.Errorf("username = %q", request.Variables["username"])
		}

		w.Header().Set("Content-Type", "application/json")
		if !strings.Contains(request.Query, `object(expression: "HEAD:.project")`) {
			t.Errorf("query does not request project metadata: %s", request.Query)
		}
		_, _ = w.Write([]byte(`{"data":{"user":{"projects":{"pageInfo":{"hasNextPage":false},"nodes":[{"name":"First","nameWithOwner":"sacha/first","url":"https://hub/1","descriptionHtml":"one","visibility":"PUBLIC","owner":{"avatarUrl":"avatar"},"defaultBranchRef":{"target":{"committedDate":"2026-01-01T00:00:00Z","abbreviatedOid":"1111111","oid":"111111111111","url":"https://hub/1/commit/1111111"}},"project":{"entries":[]}},{"name":"Hidden","url":"https://hub/2","visibility":"private","owner":{}},{"name":"Fallback","nameWithOwner":"sacha/fallback","url":"https://hub/3","descriptionHtml":"three","visibility":"PUBLIC","owner":{},"defaultBranchRef":{"target":{"committedDate":"2026-02-01T00:00:00Z","abbreviatedOid":"3333333","oid":"333333333333","url":"https://hub/3/commit/3333333"}},"project":{"entries":[{"name":"project.yaml","type":"blob","object":{"text":"name: Metadata Name\ndescription: A <safe> description\n"}},{"name":"image.webp","type":"blob","object":{}}]}}]}}}}`))
	}))
	defer server.Close()

	client := NewClient(server.Client(), ClientConfig{
		GitHubEndpoint: server.URL,
		GitHubToken:    "token",
		Username:       "sacha",
	})
	cache, err := client.Fetch(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	if len(cache.Projects) != 2 || cache.Projects[0].Name != "Metadata Name" || cache.Projects[1].Name != "First" {
		t.Fatalf("projects = %#v", cache.Projects)
	}
	if cache.Projects[0].DescriptionHTML != "A &lt;safe&gt; description" || cache.Projects[0].FirstLetter != "M" || !strings.Contains(cache.Projects[0].AvatarURL, "/333333333333/.project/image.webp") {
		t.Errorf("metadata project = %#v", cache.Projects[0])
	}
	if !cache.Projects[1].HasAvatar || cache.Projects[1].FirstLetter != "F" || cache.Projects[1].LastCommitHash != "1111111" {
		t.Errorf("standardized project = %#v", cache.Projects[1])
	}
	if !strings.HasPrefix(cache.Projects[0].HSLColor, "hsl(") {
		t.Errorf("color = %q", cache.Projects[0].HSLColor)
	}
}

func TestClientUsesRequestContext(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	defer server.Close()

	client := NewClient(server.Client(), ClientConfig{GitHubEndpoint: server.URL, GitHubToken: "token"})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := client.Fetch(ctx); err == nil {
		t.Fatal("Fetch returned no error for a canceled context")
	}
}

func TestClientPaginatesRepositories(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		var request graphQLRequest
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatal(err)
		}
		w.Header().Set("Content-Type", "application/json")
		if requests == 1 {
			_, _ = w.Write([]byte(`{"data":{"user":{"projects":{"pageInfo":{"hasNextPage":true,"endCursor":"next"},"nodes":[]}}}}`))
			return
		}
		if request.Variables["cursor"] != "next" {
			t.Errorf("cursor = %q, want next", request.Variables["cursor"])
		}
		_, _ = w.Write([]byte(`{"data":{"user":{"projects":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}`))
	}))
	defer server.Close()

	client := NewClient(server.Client(), ClientConfig{GitHubEndpoint: server.URL, GitHubToken: "token"})
	if _, err := client.Fetch(context.Background()); err != nil {
		t.Fatal(err)
	}
	if requests != 2 {
		t.Fatalf("requests = %d, want 2", requests)
	}
}

func TestClientRejectsPaginationWithoutNewCursor(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"data":{"user":{"projects":{"pageInfo":{"hasNextPage":true,"endCursor":""},"nodes":[]}}}}`))
	}))
	defer server.Close()

	client := NewClient(server.Client(), ClientConfig{GitHubEndpoint: server.URL, GitHubToken: "token"})
	if _, err := client.Fetch(context.Background()); err == nil || !strings.Contains(err.Error(), "no new cursor") {
		t.Fatalf("Fetch error = %v", err)
	}
}

func TestClientRetriesGitHubRateLimit(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests++
		if requests == 1 {
			w.Header().Set("Retry-After", "0")
			http.Error(w, "limited", http.StatusTooManyRequests)
			return
		}
		_, _ = w.Write([]byte(`{"data":{"user":{"projects":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}`))
	}))
	defer server.Close()

	client := NewClient(server.Client(), ClientConfig{GitHubEndpoint: server.URL, GitHubToken: "token"})
	if _, err := client.Fetch(context.Background()); err != nil {
		t.Fatal(err)
	}
	if requests != 2 {
		t.Fatalf("requests = %d, want 2", requests)
	}
}

func TestProjectMetadataRejectsInvalidYAMLAndEncodesImagePath(t *testing.T) {
	invalid := "name: valid\n---\n[unterminated"
	entries := []projectEntry{{Name: "project.yaml", Type: "blob"}}
	entries[0].Object.Text = &invalid
	if err := applyProjectFiles(&Project{}, "owner/repository", "commit", entries); err == nil || !strings.Contains(err.Error(), "invalid .project/project.yaml") {
		t.Fatalf("invalid YAML error = %v", err)
	}

	imageEntries := []projectEntry{{Name: "image. name#.webp", Type: "blob"}}
	project := Project{}
	if err := applyProjectFiles(&project, "owner name/repository#1", "commit hash", imageEntries); err != nil {
		t.Fatal(err)
	}
	if project.AvatarURL != "https://raw.githubusercontent.com/owner%20name/repository%231/commit%20hash/.project/image.%20name%23.webp" {
		t.Fatalf("AvatarURL = %q", project.AvatarURL)
	}
}

type staticFetcher struct {
	cache Cache
}

func (f staticFetcher) Fetch(context.Context) (Cache, error) {
	return cloneCache(f.cache), nil
}

func TestStoreLoadsRefreshesAndPreservesColors(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "projects_cache.json")
	historical := `{"version":1,"source":"github","refreshedAt":"2026-01-01T00:00:00Z","projects":[{"name":"Hub","url":"https://hub/1","descriptionHtml":"old","avatarUrl":"","first_letter":"H","hslColor":"hsl(1, 70%, 40%)","hasAvatar":false}]}`
	if err := os.WriteFile(path, []byte(historical), 0o600); err != nil {
		t.Fatal(err)
	}

	fetcher := staticFetcher{cache: Cache{
		Projects: []Project{newProject("Hub", "https://hub/1", "new", "avatar")},
	}}
	store := NewStore(path, fetcher)
	if err := store.Load(); err != nil {
		t.Fatal(err)
	}

	snapshot := store.Get()
	snapshot.Projects[0].Name = "changed by caller"
	if got := store.Get().Projects[0].Name; got != "Hub" {
		t.Fatalf("Get exposed store memory: %q", got)
	}
	if err := store.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := store.Get().Projects[0].HSLColor; got != "hsl(1, 70%, 40%)" {
		t.Fatalf("persisted color = %q", got)
	}

	reloaded := NewStore(path, nil)
	if err := reloaded.Load(); err != nil {
		t.Fatal(err)
	}
	cache := reloaded.Get()
	if cache.Projects[0].DescriptionHTML != "new" || cache.Projects[0].Name != "Hub" {
		t.Fatalf("reloaded cache = %#v", cache)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{`"descriptionHtml"`, `"avatarUrl"`, `"first_letter"`, `"hslColor"`, `"hasAvatar"`} {
		if !strings.Contains(string(data), field) {
			t.Errorf("cache does not contain historical field %s", field)
		}
	}
	matches, err := filepath.Glob(filepath.Join(dir, ".projects-cache-*"))
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 0 {
		t.Fatalf("temporary files remain: %v", matches)
	}
}

func TestStoreInvalidatesLegacyCacheAndDetectsStaleCache(t *testing.T) {
	path := filepath.Join(t.TempDir(), "projects_cache.json")
	if err := os.WriteFile(path, []byte(`{"projects":[]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	store := NewStore(path, nil)
	if err := store.Load(); err == nil || !strings.Contains(err.Error(), "obsolete format") {
		t.Fatalf("legacy Load error = %v", err)
	}

	cache := Cache{Version: cacheVersion, Source: cacheSource, RefreshedAt: time.Now().Add(-25 * time.Hour)}
	if err := writeCache(path, cache); err != nil {
		t.Fatal(err)
	}
	if err := store.Load(); err != nil {
		t.Fatal(err)
	}
	if !store.Stale(time.Now(), 24*time.Hour) {
		t.Fatal("25-hour-old cache is not stale")
	}
}
