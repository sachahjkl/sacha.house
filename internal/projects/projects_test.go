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
)

func TestClientFetchesFiltersAndReversesProjects(t *testing.T) {
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
		switch r.URL.Path {
		case "/gitlab":
			if !strings.Contains(request.Query, "projects(namespacePath: $username)") {
				t.Errorf("GitLab query does not restrict the personal namespace: %s", request.Query)
			}
			_, _ = w.Write([]byte(`{"data":{"projects":{"nodes":[{"name":"Lab","url":"https://lab/1","descriptionHtml":"<p>lab</p>","avatarUrl":"","visibility":"public"},{"name":"Secret","url":"https://lab/2","visibility":"PRIVATE"}]}}}`))
		case "/github":
			_, _ = w.Write([]byte(`{"data":{"user":{"projects":{"nodes":[{"name":"First","url":"https://hub/1","descriptionHtml":"one","visibility":"PUBLIC","owner":{"avatarUrl":"avatar"}},{"name":"Hidden","url":"https://hub/2","visibility":"private","owner":{}},{"name":"Last","url":"https://hub/3","descriptionHtml":"three","visibility":"PUBLIC","owner":{}}]}}}}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := NewClient(server.Client(), ClientConfig{
		GitLabEndpoint: server.URL + "/gitlab",
		GitHubEndpoint: server.URL + "/github",
		GitLabToken:    "token",
		GitHubToken:    "token",
		Username:       "sacha",
	})
	cache, err := client.Fetch(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	if len(cache.GitLab) != 1 || cache.GitLab[0].Name != "Lab" {
		t.Fatalf("GitLab projects = %#v", cache.GitLab)
	}
	if len(cache.GitHub) != 2 || cache.GitHub[0].Name != "Last" || cache.GitHub[1].Name != "First" {
		t.Fatalf("GitHub projects = %#v", cache.GitHub)
	}
	if !cache.GitHub[1].HasAvatar || cache.GitHub[1].FirstLetter != "F" {
		t.Errorf("standardized GitHub project = %#v", cache.GitHub[1])
	}
	if !strings.HasPrefix(cache.GitLab[0].HSLColor, "hsl(") {
		t.Errorf("color = %q", cache.GitLab[0].HSLColor)
	}
}

func TestClientUsesRequestContext(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	defer server.Close()

	client := NewClient(server.Client(), ClientConfig{GitLabEndpoint: server.URL, GitLabToken: "token"})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := client.Fetch(ctx); err == nil {
		t.Fatal("Fetch returned no error for a canceled context")
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
	historical := `{
  "gitlab": [{"name":"Lab","url":"https://lab/1","descriptionHtml":"old","avatarUrl":"","first_letter":"L","hslColor":"hsl(1, 70%, 40%)","hasAvatar":false}],
  "github": []
}`
	if err := os.WriteFile(path, []byte(historical), 0o600); err != nil {
		t.Fatal(err)
	}

	fetcher := staticFetcher{cache: Cache{
		GitLab: []Project{newProject("Lab", "https://lab/1", "new", "")},
		GitHub: []Project{newProject("Hub", "https://hub/1", "hub", "avatar")},
	}}
	store := NewStore(path, fetcher)
	if err := store.Load(); err != nil {
		t.Fatal(err)
	}

	snapshot := store.Get()
	snapshot.GitLab[0].Name = "changed by caller"
	if got := store.Get().GitLab[0].Name; got != "Lab" {
		t.Fatalf("Get exposed store memory: %q", got)
	}
	if err := store.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := store.Get().GitLab[0].HSLColor; got != "hsl(1, 70%, 40%)" {
		t.Fatalf("persisted color = %q", got)
	}

	reloaded := NewStore(path, nil)
	if err := reloaded.Load(); err != nil {
		t.Fatal(err)
	}
	cache := reloaded.Get()
	if cache.GitLab[0].DescriptionHTML != "new" || cache.GitHub[0].Name != "Hub" {
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
