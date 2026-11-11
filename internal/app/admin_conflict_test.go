package app

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAdminResolvesABlogConflict(t *testing.T) {
	application := newTestApp(t)
	cookie := adminCookie(t, application)
	post := filepath.Join(application.options.BlogRoot, "hello")
	files := map[string]string{
		"post.seed.json":  `{"id":"hello","slug":"hello","title":"Hello from the repository","language":"fr","status":"published"}`,
		"content.seed.md": "# Welcome\n\nA post from the repository.",
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(post, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	get := func(path string) *httptest.ResponseRecorder {
		request := httptest.NewRequest(http.MethodGet, path, nil)
		request.AddCookie(cookie)
		response := httptest.NewRecorder()
		application.ServeHTTP(response, request)
		return response
	}

	if body := get("/admin").Body.String(); !strings.Contains(body, "1 blogposts changed both in the repository and here") {
		t.Fatalf("the admin home does not report the conflict: %s", body)
	}
	if body := get("/admin/blogposts").Body.String(); !strings.Contains(body, `href="/admin/blogposts/hello/conflict"`) || !strings.Contains(body, "conflict-badge") {
		t.Fatalf("the list does not link the conflict: %s", body)
	}
	page := get("/admin/blogposts/hello/conflict")
	body := page.Body.String()
	for _, want := range []string{"Hello from the repository", `diff-line diff-remove`, "A public post.", `diff-line diff-add`, "A post from the repository.", "/conflict/take-repository", "/conflict/keep-site"} {
		if page.Code != http.StatusOK || !strings.Contains(body, want) {
			t.Fatalf("conflict page = %d, lacks %q: %s", page.Code, want, body)
		}
	}

	request := httptest.NewRequest(http.MethodPost, "/admin/blogposts/hello/conflict/take-repository", nil)
	request.AddCookie(cookie)
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)
	if response.Code != http.StatusSeeOther || response.Header().Get("Location") != "/admin/blogposts" {
		t.Fatalf("take repository = %d %q: %s", response.Code, response.Header().Get("Location"), response.Body.String())
	}
	document, err := application.blog.Load("hello", true)
	if err != nil || document.Metadata.Title != "Hello from the repository" || !strings.Contains(document.Markdown, "A post from the repository.") {
		t.Fatalf("document = %#v, %v", document, err)
	}
	if _, err := os.Stat(filepath.Join(post, "assets", "image.txt")); err != nil {
		t.Fatalf("the asset was lost: %v", err)
	}
	if response := get("/admin/blogposts/hello/conflict"); response.Code != http.StatusSeeOther {
		t.Fatalf("a resolved conflict page = %d, want a redirect to the editor", response.Code)
	}
}

func TestBlogSearch(t *testing.T) {
	application := newTestApp(t)
	get := func(path string) string {
		response := httptest.NewRecorder()
		application.ServeHTTP(response, httptest.NewRequest(http.MethodGet, path, nil))
		if response.Code != http.StatusOK {
			t.Fatalf("%s = %d", path, response.Code)
		}
		return response.Body.String()
	}
	if body := get("/blog?q=PUBLIC+welcome"); !strings.Contains(body, `href="/blog/hello"`) || !strings.Contains(body, "1 post matches") || !strings.Contains(body, `name="robots" content="noindex"`) {
		t.Fatalf("a matching search: %s", body)
	}
	if body := get("/blog?q=nothing-like-this"); strings.Contains(body, `href="/blog/hello"`) || !strings.Contains(body, "No post matches") {
		t.Fatalf("a search without result: %s", body)
	}
	if body := get("/"); !strings.Contains(body, `"urlTemplate":"https://sacha.house/blog?q={search_term_string}"`) {
		t.Fatalf("the WebSite has no SearchAction: %s", body)
	}
}
