package app

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"sacha.house/internal/blog"
	"sacha.house/internal/projects"
)

func TestRequestIPTrustsTheProxyOnThePrivateBridge(t *testing.T) {
	application := &App{config: Config{TrustProxyHTTPS: true}}
	request := httptest.NewRequest(http.MethodGet, "/ip", nil)
	request.RemoteAddr = "172.18.0.1:1234"
	request.Header.Set("X-Real-IP", "203.0.113.9")
	if got := application.requestIP(request); got != "203.0.113.9" {
		t.Fatalf("requestIP() = %q", got)
	}
}

func TestRequestIPIgnoresPrivatePeersWithoutTheProxySetting(t *testing.T) {
	application := &App{}
	request := httptest.NewRequest(http.MethodGet, "/ip", nil)
	request.RemoteAddr = "172.18.0.1:1234"
	request.Header.Set("X-Real-IP", "203.0.113.9")
	if got := application.requestIP(request); got != "172.18.0.1" {
		t.Fatalf("requestIP() = %q", got)
	}
}

func TestAdminSessionCheck(t *testing.T) {
	application := newTestApp(t)
	anonymous := httptest.NewRecorder()
	application.ServeHTTP(anonymous, httptest.NewRequest(http.MethodGet, "/admin/session", nil))
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status = %d", anonymous.Code)
	}
	request := httptest.NewRequest(http.MethodGet, "/admin/session", nil)
	request.AddCookie(adminCookie(t, application))
	signedIn := httptest.NewRecorder()
	application.ServeHTTP(signedIn, request)
	if signedIn.Code != http.StatusNoContent {
		t.Fatalf("signed-in status = %d", signedIn.Code)
	}
}

func TestExpiredDatastarRequestIsNotRedirectedToTheLoginPage(t *testing.T) {
	application := newTestApp(t)
	request := httptest.NewRequest(http.MethodPost, "/admin/refresh-projects", nil)
	request.Header.Set("Datastar-Request", "true")
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d", response.Code)
	}
}

func TestDraftImagesShowInTheAdminPreviewOnly(t *testing.T) {
	application := newTestApp(t)
	if _, err := application.blog.Save(blog.SaveInput{Title: "Draft", Slug: "draft", Language: "en", Markdown: "text"}, ""); err != nil {
		t.Fatal(err)
	}
	upload, err := application.blog.Upload("draft", "image.png", "image/png", []byte("png"))
	if err != nil {
		t.Fatal(err)
	}
	target := "/media/blog/draft/assets/" + path.Base(upload.URL)

	anonymous := httptest.NewRecorder()
	application.ServeHTTP(anonymous, httptest.NewRequest(http.MethodGet, target, nil))
	if anonymous.Code != http.StatusNotFound {
		t.Fatalf("anonymous status = %d", anonymous.Code)
	}
	request := httptest.NewRequest(http.MethodGet, target, nil)
	request.AddCookie(adminCookie(t, application))
	admin := httptest.NewRecorder()
	application.ServeHTTP(admin, request)
	if admin.Code != http.StatusOK || admin.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("admin status = %d, Cache-Control = %q", admin.Code, admin.Header().Get("Cache-Control"))
	}
}

func TestStaleEditorKeepsItsTextOnConflict(t *testing.T) {
	application := newTestApp(t)
	form := url.Values{"title": {"Hello"}, "slug": {"hello"}, "language": {"en"}, "status": {"draft"}, "markdown": {"my long edit"}, "revision": {"2000-01-01T00:00:00Z"}}
	request := httptest.NewRequest(http.MethodPost, "/admin/blogposts/hello/save", strings.NewReader(form.Encode()))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.AddCookie(adminCookie(t, application))
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)
	if response.Code != http.StatusUnprocessableEntity || !strings.Contains(response.Body.String(), "my long edit") {
		t.Fatalf("status = %d, body keeps the text = %t", response.Code, strings.Contains(response.Body.String(), "my long edit"))
	}
}

func TestLargeAccentedPostFitsTheForm(t *testing.T) {
	application := newTestApp(t)
	markdown := strings.Repeat("é", 500_000) // 1 MB of Markdown, 3 MB once percent-encoded
	form := url.Values{"title": {"Big"}, "slug": {"big"}, "language": {"fr"}, "status": {"draft"}, "markdown": {markdown}}
	request := httptest.NewRequest(http.MethodPost, "/admin/blogposts/new", strings.NewReader(form.Encode()))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.AddCookie(adminCookie(t, application))
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)
	if response.Code != http.StatusSeeOther {
		t.Fatalf("status = %d", response.Code)
	}
}

type countingProjectsFetcher struct{ calls *atomic.Int32 }

func (fetcher countingProjectsFetcher) Fetch(context.Context) (projects.Cache, error) {
	fetcher.calls.Add(1)
	return projects.Cache{}, context.DeadlineExceeded
}

func TestStaleProjectsAreRefreshedByReadersWithBackoff(t *testing.T) {
	calls := &atomic.Int32{}
	application := newTestAppWithFetcher(t, countingProjectsFetcher{calls: calls}, false)
	now := time.Date(2026, time.January, 1, 0, 0, 0, 0, time.UTC).Add(projectsCacheMaxAge + time.Hour)
	application.options.Now = func() time.Time { return now }
	visit := func() {
		t.Helper()
		application.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/projects", nil))
		deadline := time.Now().Add(time.Second)
		for len(application.projectsRefresh) != 0 && time.Now().Before(deadline) {
			time.Sleep(time.Millisecond)
		}
	}

	visit()
	visit()
	if got := calls.Load(); got != 1 {
		t.Fatalf("fetches after two visits = %d, want 1", got)
	}
	now = now.Add(projectsRetryInterval)
	visit()
	if got := calls.Load(); got != 2 {
		t.Fatalf("fetches after the retry interval = %d, want 2", got)
	}
}
