package paste

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type gistTestServer struct {
	mu       sync.Mutex
	gist     Gist
	requests int
}

func (server *gistTestServer) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	server.mu.Lock()
	defer server.mu.Unlock()
	server.requests++
	if request.Header.Get("Authorization") != "Bearer test-token" || request.Header.Get("X-Github-Api-Version") != gistAPIVersion {
		http.Error(writer, "bad credentials", http.StatusUnauthorized)
		return
	}
	writer.Header().Set("Content-Type", "application/json")
	switch {
	case request.Method == http.MethodGet && request.URL.Path == "/gists":
		if server.gist.ID == "" {
			_, _ = writer.Write([]byte("[]"))
		} else {
			_ = json.NewEncoder(writer).Encode([]Gist{server.gist})
		}
	case request.Method == http.MethodPost && request.URL.Path == "/gists":
		var input GistCreate
		_ = json.NewDecoder(request.Body).Decode(&input)
		server.gist = Gist{ID: "aabbcc", Description: input.Description, CreatedAt: "2026-01-01T00:00:00Z", UpdatedAt: "2026-01-01T00:00:00Z", Files: map[string]GistFile{}, History: []GistHistory{{Version: "01"}}}
		for name, file := range input.Files {
			server.gist.Files[name] = GistFile{Filename: name, Content: file.Content}
		}
		writer.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(writer).Encode(server.gist)
	case request.Method == http.MethodGet && request.URL.Path == "/gists/aabbcc" && server.gist.ID != "":
		_ = json.NewEncoder(writer).Encode(server.gist)
	case request.Method == http.MethodPatch && request.URL.Path == "/gists/aabbcc" && server.gist.ID != "":
		var input GistUpdate
		_ = json.NewDecoder(request.Body).Decode(&input)
		for name, file := range input.Files {
			server.gist.Files[name] = GistFile{Filename: name, Content: file.Content}
		}
		next := "02"
		if server.gist.History[0].Version == "02" {
			next = "03"
		}
		server.gist.History = []GistHistory{{Version: next}}
		server.gist.UpdatedAt = "2026-01-02T00:00:00Z"
		_ = json.NewEncoder(writer).Encode(server.gist)
	case request.Method == http.MethodDelete && request.URL.Path == "/gists/aabbcc" && server.gist.ID != "":
		server.gist = Gist{}
		writer.WriteHeader(http.StatusNoContent)
	default:
		http.NotFound(writer, request)
	}
}

func TestStoreCRUDRevisionAndRotationWithGitHubServer(t *testing.T) {
	remote := &gistTestServer{}
	server := httptest.NewTLSServer(remote)
	defer server.Close()
	client, err := NewGistClient(server.URL, "test-token", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	oldCodec, _ := NewCodec(testSecrets("old"))
	store, err := NewStore(client, oldCodec, 1024, 20)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	created, err := store.Create(ctx, Input{Title: "First", Body: "secret"}, 1000)
	if err != nil {
		t.Fatal(err)
	}
	if created.GistID != "aabbcc" || created.Revision != "01" || created.Document.Body != "secret" {
		t.Fatalf("created = %#v", created)
	}
	items, truncated, err := store.List(ctx)
	if err != nil || truncated || len(items) != 1 || items[0].Title != "First" {
		t.Fatalf("list = %#v, %v, %v", items, truncated, err)
	}
	if _, err := store.Update(ctx, created.GistID, "ff", Input{Title: "Lost", Body: "write"}, 2000); ErrorKindOf(err) != ErrorConflict {
		t.Fatalf("conflict error = %v", err)
	}
	updated, err := store.Update(ctx, created.GistID, created.Revision, Input{Title: "Second", Body: "changed"}, 2000)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Revision != "02" || updated.Document.CreatedMS != 1000 || updated.Document.UpdatedMS != 2000 {
		t.Fatalf("updated = %#v", updated)
	}
	newCodec, _ := NewCodec(testSecrets("new"))
	rotatingStore, _ := NewStore(client, newCodec, 1024, 20)
	beforeRotation, err := rotatingStore.Get(ctx, created.GistID)
	if err != nil || !beforeRotation.NeedsRotation {
		t.Fatalf("before rotation = %#v, %v", beforeRotation, err)
	}
	rotated, err := rotatingStore.Rotate(ctx, created.GistID, updated.Revision)
	if err != nil {
		t.Fatal(err)
	}
	if rotated.KeyID != "new" || rotated.PasteID != created.PasteID || rotated.Document != updated.Document {
		t.Fatalf("rotated = %#v", rotated)
	}
	if err := rotatingStore.Delete(ctx, created.GistID, rotated.Revision); err != nil {
		t.Fatal(err)
	}
	if _, err := rotatingStore.Get(ctx, created.GistID); ErrorKindOf(err) != ErrorNotFound {
		t.Fatalf("get after delete = %v", err)
	}
}

func TestGistClientContextAndErrors(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		switch request.URL.Query().Get("page") {
		case "1":
			writer.Header().Set("Retry-After", "17")
			http.Error(writer, "limited", http.StatusTooManyRequests)
		case "2":
			_, _ = writer.Write([]byte("not-json"))
		default:
			<-request.Context().Done()
		}
	}))
	defer server.Close()
	client, err := NewGistClient(server.URL, "token", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := client.List(context.Background(), 1, 1); gistKind(err) != GistRateLimited {
		t.Fatalf("rate error = %v", err)
	}
	if _, _, err := client.List(context.Background(), 2, 1); gistKind(err) != GistMalformedResponse {
		t.Fatalf("JSON error = %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Millisecond)
	defer cancel()
	if _, _, err := client.List(ctx, 3, 1); gistKind(err) != GistTimeout {
		t.Fatalf("timeout error = %v", err)
	}
}

func TestStoreListUsesStablePageSize(t *testing.T) {
	var queries []string
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		queries = append(queries, request.URL.RawQuery)
		if request.URL.Query().Get("page") == "1" {
			writer.Header().Set("Link", `<https://api.github.test/gists?per_page=100&page=2>; rel="next"`)
		}
		gists := make([]Gist, gistPageSize)
		_ = json.NewEncoder(writer).Encode(gists)
	}))
	defer server.Close()
	client, err := NewGistClient(server.URL, "token", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	codec, err := NewCodec(testSecrets("old"))
	if err != nil {
		t.Fatal(err)
	}
	store, err := NewStore(client, codec, 1024, 150)
	if err != nil {
		t.Fatal(err)
	}
	items, truncated, err := store.List(context.Background())
	if err != nil || !truncated || len(items) != 0 {
		t.Fatalf("list = %#v, %v, %v", items, truncated, err)
	}
	want := []string{"per_page=100&page=1", "per_page=100&page=2"}
	if len(queries) != len(want) || queries[0] != want[0] || queries[1] != want[1] {
		t.Fatalf("queries = %q, want %q", queries, want)
	}
}

func TestGistClientSuccessfulMutationInvalidBodyHasUnknownOutcome(t *testing.T) {
	tests := []struct {
		name   string
		method string
		body   string
	}{
		{name: "create malformed body can duplicate", method: http.MethodPost, body: "not-json"},
		{name: "update oversized body can overwrite", method: http.MethodPatch, body: strings.Repeat(" ", gistMaxResponseBytes+1)},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
				if request.Method != test.method {
					t.Fatalf("method = %s, want %s", request.Method, test.method)
				}
				if test.method == http.MethodPost {
					writer.WriteHeader(http.StatusCreated)
				}
				_, _ = writer.Write([]byte(test.body))
			}))
			defer server.Close()
			client, err := NewGistClient(server.URL, "token", server.Client())
			if err != nil {
				t.Fatal(err)
			}
			if test.method == http.MethodPost {
				_, err = client.Create(context.Background(), GistCreate{})
			} else {
				_, err = client.Update(context.Background(), "aabbcc", GistUpdate{})
			}
			if gistKind(err) != GistOutcomeUnknown || ErrorKindOf(gistError(err)) != ErrorOutcomeUnknown {
				t.Fatalf("error = %v, gist kind = %d, paste kind = %d", err, gistKind(err), ErrorKindOf(gistError(err)))
			}
		})
	}
}

func TestGistClientAmbiguousMutationStatusHasUnknownOutcome(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		http.Error(writer, "gateway timeout", http.StatusGatewayTimeout)
	}))
	defer server.Close()
	client, err := NewGistClient(server.URL, "token", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.Create(context.Background(), GistCreate{})
	if gistKind(err) != GistOutcomeUnknown || ErrorKindOf(gistError(err)) != ErrorOutcomeUnknown {
		t.Fatalf("error = %v, gist kind = %d, paste kind = %d", err, gistKind(err), ErrorKindOf(gistError(err)))
	}
}

func gistKind(err error) GistErrorKind {
	if remote, ok := err.(*GistError); ok {
		return remote.Kind
	}
	return 0
}
