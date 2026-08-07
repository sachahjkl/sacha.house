package app

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"testing/fstest"
	"time"

	"sacha.house/internal/auth"
	"sacha.house/internal/paste"
	"sacha.house/internal/projects"
)

type testProjectsFetcher struct{}

func (testProjectsFetcher) Fetch(context.Context) (projects.Cache, error) {
	return projects.Cache{GitHub: []projects.Project{{Name: "Refreshed", URL: "https://example.com/refreshed"}}}, nil
}

func newTestApp(t *testing.T) *App {
	t.Helper()
	root := t.TempDir()
	blogRoot := filepath.Join(root, "blog")
	postRoot := filepath.Join(blogRoot, "hello")
	if err := os.MkdirAll(filepath.Join(postRoot, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	metadata := `{"id":"hello","slug":"hello","title":"Hello & Go","language":"fr","status":"published","publishedAt":"2026-01-02T12:00:00Z","updatedAt":"2026-01-03T12:00:00Z","createdAt":"2025-01-01T12:00:00Z","author":"Sacha Froment"}`
	if err := os.WriteFile(filepath.Join(postRoot, "post.json"), []byte(metadata), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(postRoot, "content.md"), []byte("# Welcome\n\nA public post."), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(postRoot, "assets", "image.txt"), []byte("media"), 0o644); err != nil {
		t.Fatal(err)
	}
	projectsPath := filepath.Join(root, "projects.json")
	if err := os.WriteFile(projectsPath, []byte(`{"gitlab":[],"github":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	assets := fstest.MapFS{
		"linkedin_profile.json": &fstest.MapFile{Data: []byte(`{"experiences":[],"education":[]}`)},
		"hello.txt":             &fstest.MapFile{Data: []byte("static")},
		"js/navigation.js":      &fstest.MapFile{Data: []byte("if (!patched) throw error('failed')")},
	}
	hash, err := auth.HashPassword("test-password", []byte("test-pepper"))
	if err != nil {
		t.Fatal(err)
	}
	config := Config{
		GitRepoID: "owner/repository", AdminPasswordHash: hash, AdminPasswordPepper: "test-pepper",
		WebAuthnCredentialsFile: filepath.Join(root, "passkeys.json"),
	}
	application, err := NewWithOptions(config, Options{
		BlogRoot: blogRoot, ProjectsPath: projectsPath, StaticFS: assets,
		ProjectsFetcher: testProjectsFetcher{}, Development: true,
		Version: "test", CommitHash: "abc123", Now: func() time.Time {
			return time.Date(2026, time.January, 1, 0, 0, 0, 0, time.UTC)
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	return application
}

func TestPublicRoutes(t *testing.T) {
	application := newTestApp(t)
	tests := []struct {
		path        string
		status      int
		contentType string
		contains    string
	}{
		{path: "/", status: 200, contentType: "text/html", contains: "welcome to my website"},
		{path: "/blog", status: 200, contentType: "text/html", contains: "Hello &amp; Go"},
		{path: "/blog/hello", status: 200, contentType: "text/html", contains: "A public post."},
		{path: "/blog/missing", status: 404, contentType: "text/plain", contains: "404 page not found"},
		{path: "/blog/rss.xml", status: 200, contentType: "application/rss+xml", contains: "Hello &amp; Go"},
		{path: "/blog/atom.xml", status: 200, contentType: "application/atom+xml", contains: "Hello &amp; Go"},
		{path: "/about", status: 200, contentType: "text/html", contains: "Professional Details"},
		{path: "/resume", status: 200, contentType: "text/html", contains: "CV de Sacha Froment"},
		{path: "/resume?lang=en", status: 200, contentType: "text/html", contains: "Résumé — Sacha Froment"},
		{path: "/cv", status: 200, contentType: "text/html", contains: "Catalogue de projets"},
		{path: "/cv?lang=en", status: 200, contentType: "text/html", contains: "Project catalog"},
		{path: "/projects", status: 200, contentType: "text/html", contains: "GitLab"},
		{path: "/teapot", status: 200, contentType: "text/html", contains: "nice cup"},
		{path: "/teapot?drink=coffee", status: 418, contentType: "text/html", contains: "418 I'm a teapot"},
		{path: "/ping", status: 200, contentType: "text/plain", contains: "pong"},
		{path: "/ip", status: 200, contentType: "text/plain", contains: "192.0.2.1"},
		{path: "/api/ip", status: 200, contentType: "text/plain", contains: "192.0.2.1"},
		{path: "/static/hello.txt", status: 200, contentType: "text/plain", contains: "static"},
		{path: "/media/blog/hello/assets/image.txt", status: 200, contentType: "text/plain", contains: "media"},
		{path: "/linkedin_profile.json", status: 404, contentType: "text/plain", contains: "404 page not found"},
		{path: "/unknown", status: 404, contentType: "text/plain", contains: "404 page not found"},
	}
	for _, test := range tests {
		t.Run(test.path, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodGet, test.path, nil)
			request.RemoteAddr = "192.0.2.1:1234"
			response := httptest.NewRecorder()
			application.ServeHTTP(response, request)
			if response.Code != test.status {
				t.Fatalf("status = %d, want %d; body: %s", response.Code, test.status, response.Body.String())
			}
			if contentType := response.Header().Get("Content-Type"); !strings.HasPrefix(contentType, test.contentType) {
				t.Errorf("Content-Type = %q, want prefix %q", contentType, test.contentType)
			}
			if !strings.Contains(response.Body.String(), test.contains) {
				t.Errorf("body does not contain %q", test.contains)
			}
		})
	}

	request := httptest.NewRequest(http.MethodGet, "/mariage", nil)
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)
	if response.Code != http.StatusFound || response.Header().Get("Location") != "/static/Patricia_et_Sacha_Invitation.pdf" {
		t.Fatalf("mariage redirect = %d %q", response.Code, response.Header().Get("Location"))
	}

	legacyCV := httptest.NewRecorder()
	application.ServeHTTP(legacyCV, httptest.NewRequest(http.MethodGet, "/cv.html", nil))
	if legacyCV.Code != http.StatusMovedPermanently || legacyCV.Header().Get("Location") != "/cv" {
		t.Fatalf("legacy CV redirect = %d %q", legacyCV.Code, legacyCV.Header().Get("Location"))
	}
}

func TestRequestIPUsesTrustedProxyHeaders(t *testing.T) {
	application := &App{config: Config{TrustProxyHTTPS: true}}
	request := httptest.NewRequest(http.MethodGet, "/ip", nil)
	request.RemoteAddr = "127.0.0.1:1234"
	request.Header.Set("X-Forwarded-For", "198.51.100.1, 203.0.113.2")
	request.Header.Set("X-Real-IP", "192.0.2.3")
	if got := application.requestIP(request); got != "192.0.2.3" {
		t.Fatalf("requestIP() = %q", got)
	}

	request.Header.Del("X-Real-IP")
	if got := application.requestIP(request); got != "203.0.113.2" {
		t.Fatalf("requestIP() with X-Forwarded-For = %q", got)
	}
}

func TestRequestIPIgnoresUntrustedProxyHeaders(t *testing.T) {
	application := &App{}
	request := httptest.NewRequest(http.MethodGet, "/ip", nil)
	request.RemoteAddr = "127.0.0.1:1234"
	request.Header.Set("X-Real-IP", "192.0.2.3")
	if got := application.requestIP(request); got != "127.0.0.1" {
		t.Fatalf("requestIP() = %q", got)
	}
}

func TestRequestIPIgnoresHeadersFromNonLocalProxy(t *testing.T) {
	application := &App{config: Config{TrustProxyHTTPS: true}}
	request := httptest.NewRequest(http.MethodGet, "/ip", nil)
	request.RemoteAddr = "198.51.100.8:1234"
	request.Header.Set("X-Real-IP", "192.0.2.3")
	if got := application.requestIP(request); got != "198.51.100.8" {
		t.Fatalf("requestIP() = %q", got)
	}
}

func TestPublicAssetCacheHeaders(t *testing.T) {
	application := newTestApp(t)
	staticResponse := httptest.NewRecorder()
	application.ServeHTTP(staticResponse, httptest.NewRequest(http.MethodGet, "/static/hello.txt", nil))
	if got := staticResponse.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("static Cache-Control = %q, want no-store", got)
	}
	mediaResponse := httptest.NewRecorder()
	application.ServeHTTP(mediaResponse, httptest.NewRequest(http.MethodGet, "/media/blog/hello/assets/image.txt", nil))
	if got := mediaResponse.Header().Get("Cache-Control"); got != publicCache {
		t.Errorf("media Cache-Control = %q, want %q", got, publicCache)
	}
	for _, requestPath := range []string{"/blog/rss.xml", "/blog/atom.xml"} {
		response := httptest.NewRecorder()
		application.ServeHTTP(response, httptest.NewRequest(http.MethodGet, requestPath, nil))
		if got := response.Header().Get("Cache-Control"); got != feedCache {
			t.Errorf("%s Cache-Control = %q, want %q", requestPath, got, feedCache)
		}
	}
}

func TestPageLanguageAndCreatedDate(t *testing.T) {
	application := newTestApp(t)

	home := httptest.NewRecorder()
	application.ServeHTTP(home, httptest.NewRequest(http.MethodGet, "/", nil))
	if !strings.Contains(home.Body.String(), `<html lang="en">`) {
		t.Fatalf("home language is not English: %s", home.Body.String())
	}

	post := httptest.NewRecorder()
	application.ServeHTTP(post, httptest.NewRequest(http.MethodGet, "/blog/hello", nil))
	body := post.Body.String()
	if !strings.Contains(body, `<html lang="fr">`) {
		t.Fatalf("post language is not French: %s", body)
	}
	if !strings.Contains(body, `created on 01/01/2025`) || strings.Contains(body, `created on 02/01/2026`) {
		t.Fatalf("post creation date does not use CreatedAt: %s", body)
	}

	index := httptest.NewRecorder()
	application.ServeHTTP(index, httptest.NewRequest(http.MethodGet, "/blog", nil))
	if !strings.Contains(index.Body.String(), ">2026</h3>") || strings.Contains(index.Body.String(), ">2025</h3>") {
		t.Fatalf("blog index does not group by PublishedAt: %s", index.Body.String())
	}

	atom := httptest.NewRecorder()
	application.ServeHTTP(atom, httptest.NewRequest(http.MethodGet, "/blog/atom.xml", nil))
	if !strings.Contains(atom.Body.String(), `<entry xml:lang="fr">`) {
		t.Fatalf("Atom entry lacks its language: %s", atom.Body.String())
	}
	if !strings.Contains(atom.Body.String(), "\n  <entry") || !strings.Contains(atom.Body.String(), "\n    <title>") {
		t.Fatalf("Atom feed is not indented: %s", atom.Body.String())
	}

	rss := httptest.NewRecorder()
	application.ServeHTTP(rss, httptest.NewRequest(http.MethodGet, "/blog/rss.xml", nil))
	if !strings.Contains(rss.Body.String(), "\n    <item>") || !strings.Contains(rss.Body.String(), "\n      <title>") {
		t.Fatalf("RSS feed is not indented: %s", rss.Body.String())
	}
}

func TestMediaRejectsNonAssetPaths(t *testing.T) {
	application := newTestApp(t)
	request := httptest.NewRequest(http.MethodGet, "/media/blog/hello/assets/%2e%2e/post.json", nil)
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)
	if response.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", response.Code)
	}
}

func TestDatastarNavigationSendsOneDocumentPatch(t *testing.T) {
	application := newTestApp(t)
	request := httptest.NewRequest(http.MethodGet, "/about?from=home&datastar=%7B%7D", nil)
	request.Header.Set("Datastar-Request", "true")
	request.Header.Set("Datastar-History", "replace")
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)

	body := response.Body.String()
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", response.Code)
	}
	if response.Header().Get("Content-Type") != "text/event-stream" {
		t.Fatalf("Content-Type = %q", response.Header().Get("Content-Type"))
	}
	if count := strings.Count(body, "event: datastar-patch-elements"); count != 1 {
		t.Fatalf("patch event count = %d, want 1", count)
	}
	for _, value := range []string{
		`id="page-title"`,
		`id="page-body"`,
		`id="datastar-navigation" hidden`,
		`data-url="/about?from=home"`,
		`data-history="replace"`,
		`data-status="200"`,
	} {
		if !strings.Contains(body, value) {
			t.Errorf("SSE body does not contain %q", value)
		}
	}
}

func TestHomePreservesASCIILogoLines(t *testing.T) {
	application := newTestApp(t)
	response := httptest.NewRecorder()
	application.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/", nil))
	body := response.Body.String()
	if !strings.Contains(body, "▄▄▄\n▓██░") {
		t.Fatal("ASCII logo lines were collapsed")
	}
}

func TestAdminScriptLoadsOnlyOnAdminPages(t *testing.T) {
	application := newTestApp(t)
	home := httptest.NewRecorder()
	application.ServeHTTP(home, httptest.NewRequest(http.MethodGet, "/", nil))
	if strings.Contains(home.Body.String(), "/static/js/admin.js") {
		t.Fatal("public page loads admin JavaScript")
	}
	login := httptest.NewRecorder()
	application.ServeHTTP(login, httptest.NewRequest(http.MethodGet, "/admin/login", nil))
	if !strings.Contains(login.Body.String(), "/static/js/admin.js") {
		t.Fatal("admin page does not load admin JavaScript")
	}
}

func TestDatastarTeapotKeepsLogicalStatus(t *testing.T) {
	application := newTestApp(t)
	request := httptest.NewRequest(http.MethodGet, "/teapot?drink=coffee", nil)
	request.Header.Set("Accept", "text/event-stream")
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", response.Code)
	}
	if !strings.Contains(response.Body.String(), `data-status="418"`) {
		t.Fatalf("SSE body lacks logical 418 status: %s", response.Body.String())
	}
}

func TestDatastarNavigationNegotiatesCompression(t *testing.T) {
	application := newTestApp(t)
	request := httptest.NewRequest(http.MethodGet, "/about", nil)
	request.Header.Set("Datastar-Request", "true")
	request.Header.Set("Accept-Encoding", "gzip, deflate, br, zstd")
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", response.Code)
	}
	if encoding := response.Header().Get("Content-Encoding"); encoding != "br" {
		t.Fatalf("Content-Encoding = %q, want %q", encoding, "br")
	}
}

func TestNavigationControllerAcceptsPatchedErrorPage(t *testing.T) {
	application := newTestApp(t)
	response := httptest.NewRecorder()
	application.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/static/js/navigation.js", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", response.Code)
	}
	if !strings.Contains(response.Body.String(), "if (!patched)") {
		t.Fatalf("navigation controller rejects patched error pages: %s", response.Body.String())
	}
}

func TestAdminPasswordLoginAndProtection(t *testing.T) {
	application := newTestApp(t)

	response := httptest.NewRecorder()
	application.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/admin", nil))
	if response.Code != http.StatusSeeOther || response.Header().Get("Location") != "/admin/login" {
		t.Fatalf("protected route = %d %q", response.Code, response.Header().Get("Location"))
	}

	wrong := httptest.NewRequest(http.MethodPost, "/admin/login", strings.NewReader(url.Values{"password": {"wrong"}}.Encode()))
	wrong.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	wrongResponse := httptest.NewRecorder()
	application.ServeHTTP(wrongResponse, wrong)
	if wrongResponse.Code != http.StatusUnprocessableEntity || !strings.Contains(wrongResponse.Body.String(), "Invalid password") {
		t.Fatalf("wrong login = %d %s", wrongResponse.Code, wrongResponse.Body.String())
	}

	login := httptest.NewRequest(http.MethodPost, "/admin/login", strings.NewReader(url.Values{"password": {"test-password"}}.Encode()))
	login.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	loginResponse := httptest.NewRecorder()
	application.ServeHTTP(loginResponse, login)
	if loginResponse.Code != http.StatusSeeOther || loginResponse.Header().Get("Location") != "/admin" {
		t.Fatalf("login = %d %q", loginResponse.Code, loginResponse.Header().Get("Location"))
	}
	cookie := loginResponse.Result().Cookies()[0]
	if cookie.Secure || !cookie.HttpOnly || cookie.SameSite != http.SameSiteStrictMode {
		t.Fatalf("development session cookie = %#v", cookie)
	}

	admin := httptest.NewRequest(http.MethodGet, "/admin", nil)
	admin.AddCookie(cookie)
	adminResponse := httptest.NewRecorder()
	application.ServeHTTP(adminResponse, admin)
	if adminResponse.Code != http.StatusOK || !strings.Contains(adminResponse.Body.String(), "Manage blogposts") {
		t.Fatalf("admin page = %d %s", adminResponse.Code, adminResponse.Body.String())
	}

	getLogout := httptest.NewRecorder()
	application.ServeHTTP(getLogout, httptest.NewRequest(http.MethodGet, "/admin/logout", nil))
	if getLogout.Code != http.StatusNotFound {
		t.Fatalf("GET logout status = %d", getLogout.Code)
	}
}

func TestAdminRejectsCrossOriginPost(t *testing.T) {
	application := newTestApp(t)
	request := httptest.NewRequest(http.MethodPost, "/admin/login", strings.NewReader("password=test-password"))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.Header.Set("Origin", "https://attacker.example")
	request.Header.Set("Sec-Fetch-Site", "cross-site")
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("cross-origin login status = %d, want 403", response.Code)
	}
}

func TestAdminResponsesDisableCaching(t *testing.T) {
	application := newTestApp(t)
	response := httptest.NewRecorder()
	application.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/admin/login", nil))
	if value := response.Header().Get("Cache-Control"); value != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", value)
	}
}

func TestAdminDatastarFormErrorUsesLogical422(t *testing.T) {
	application := newTestApp(t)
	request := httptest.NewRequest(http.MethodPost, "/admin/login", strings.NewReader("password=wrong"))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.Header.Set("Datastar-Request", "true")
	response := httptest.NewRecorder()
	application.ServeHTTP(response, request)
	if response.Code != http.StatusOK || response.Header().Get("Content-Type") != "text/event-stream" {
		t.Fatalf("enhanced error = %d %q", response.Code, response.Header().Get("Content-Type"))
	}
	if !strings.Contains(response.Body.String(), `data-status="422"`) || !strings.Contains(response.Body.String(), "Invalid password") {
		t.Fatalf("enhanced error body = %s", response.Body.String())
	}
}

func TestAdminBlogCRUDAndProjectRefresh(t *testing.T) {
	application := newTestApp(t)
	cookie := adminCookie(t, application)

	createForm := url.Values{
		"title": {"New Post"}, "slug": {"new-post"}, "language": {"fr"}, "status": {"draft"}, "markdown": {"# Preview"},
	}
	create := httptest.NewRequest(http.MethodPost, "/admin/blogposts/new", strings.NewReader(createForm.Encode()))
	create.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	create.AddCookie(cookie)
	createResponse := httptest.NewRecorder()
	application.ServeHTTP(createResponse, create)
	if createResponse.Code != http.StatusSeeOther || createResponse.Header().Get("Location") != "/admin/blogposts/new-post" {
		t.Fatalf("create = %d %q: %s", createResponse.Code, createResponse.Header().Get("Location"), createResponse.Body.String())
	}

	edit := httptest.NewRequest(http.MethodGet, "/admin/blogposts/new-post", nil)
	edit.AddCookie(cookie)
	editResponse := httptest.NewRecorder()
	application.ServeHTTP(editResponse, edit)
	if editResponse.Code != http.StatusOK || !strings.Contains(editResponse.Body.String(), "<h1>Preview</h1>") || !strings.Contains(editResponse.Body.String(), `<option value="fr" class="bg-bgColor text-textColor" selected>`) {
		t.Fatalf("editor = %d %s", editResponse.Code, editResponse.Body.String())
	}

	saveForm := url.Values{
		"title": {"Renamed Post"}, "slug": {"renamed-post"}, "language": {"fr"}, "status": {"published"}, "markdown": {"Published"},
	}
	save := httptest.NewRequest(http.MethodPost, "/admin/blogposts/new-post/save", strings.NewReader(saveForm.Encode()))
	save.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	save.AddCookie(cookie)
	saveResponse := httptest.NewRecorder()
	application.ServeHTTP(saveResponse, save)
	if saveResponse.Code != http.StatusSeeOther || saveResponse.Header().Get("Location") != "/admin/blogposts/renamed-post" {
		t.Fatalf("save = %d %q: %s", saveResponse.Code, saveResponse.Header().Get("Location"), saveResponse.Body.String())
	}
	document, err := application.blog.Load("renamed-post", false)
	if err != nil || document.Metadata.Language != "fr" {
		t.Fatalf("saved language = %q, %v", document.Metadata.Language, err)
	}

	png, err := base64.StdEncoding.DecodeString("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
	if err != nil {
		t.Fatal(err)
	}
	uploadBody := fmt.Sprintf(`{"slug":"renamed-post","filename":"pixel.png","mimeType":"image/png","dataBase64":%q}`,
		base64.StdEncoding.EncodeToString(png))
	upload := httptest.NewRequest(http.MethodPost, "/admin/blogposts/upload-image", strings.NewReader(uploadBody))
	upload.Header.Set("Content-Type", "application/json")
	upload.AddCookie(cookie)
	uploadResponse := httptest.NewRecorder()
	application.ServeHTTP(uploadResponse, upload)
	if uploadResponse.Code != http.StatusOK || !strings.Contains(uploadResponse.Body.String(), "/media/blog/renamed-post/assets/") {
		t.Fatalf("upload = %d %s", uploadResponse.Code, uploadResponse.Body.String())
	}

	refresh := httptest.NewRequest(http.MethodPost, "/admin/refresh-projects", nil)
	refresh.AddCookie(cookie)
	refreshResponse := httptest.NewRecorder()
	application.ServeHTTP(refreshResponse, refresh)
	if refreshResponse.Code != http.StatusSeeOther || application.projects.Get().GitHub[0].Name != "Refreshed" {
		t.Fatalf("refresh = %d, cache = %#v", refreshResponse.Code, application.projects.Get())
	}
}

func TestAdminWebAuthnChallengeConfigAndPasskeyFragment(t *testing.T) {
	application := newTestApp(t)
	challengeResponse := httptest.NewRecorder()
	application.ServeHTTP(challengeResponse, httptest.NewRequest(http.MethodGet, "/admin/webauthn/login-challenge", nil))
	if challengeResponse.Code != http.StatusOK {
		t.Fatalf("challenge status = %d: %s", challengeResponse.Code, challengeResponse.Body.String())
	}
	var challenge struct {
		PublicKey struct {
			RPID string `json:"rpId"`
		} `json:"publicKey"`
	}
	if err := json.Unmarshal(challengeResponse.Body.Bytes(), &challenge); err != nil {
		t.Fatal(err)
	}
	if challenge.PublicKey.RPID != "localhost" {
		t.Fatalf("RP ID = %q", challenge.PublicKey.RPID)
	}
	ceremony := challengeResponse.Result().Cookies()[0]
	if ceremony.Secure || !ceremony.HttpOnly || ceremony.SameSite != http.SameSiteStrictMode {
		t.Fatalf("ceremony cookie = %#v", ceremony)
	}

	cookie := adminCookie(t, application)
	registration := httptest.NewRequest(http.MethodGet, "/admin/webauthn/register-challenge?label=Test", nil)
	registration.AddCookie(cookie)
	registrationResponse := httptest.NewRecorder()
	application.ServeHTTP(registrationResponse, registration)
	if registrationResponse.Code != http.StatusOK || !strings.Contains(registrationResponse.Body.String(), `"publicKey"`) {
		t.Fatalf("registration challenge = %d %s", registrationResponse.Code, registrationResponse.Body.String())
	}

	fragment := httptest.NewRequest(http.MethodGet, "/admin/webauthn/passkeys", nil)
	fragment.Header.Set("Datastar-Request", "true")
	fragment.AddCookie(cookie)
	fragmentResponse := httptest.NewRecorder()
	application.ServeHTTP(fragmentResponse, fragment)
	if fragmentResponse.Code != http.StatusOK || !strings.Contains(fragmentResponse.Body.String(), "#passkey-list") {
		t.Fatalf("passkey fragment = %d %s", fragmentResponse.Code, fragmentResponse.Body.String())
	}
}

func adminCookie(t *testing.T, application *App) *http.Cookie {
	t.Helper()
	response := httptest.NewRecorder()
	if _, err := application.auth.StartSession(response, adminUserID); err != nil {
		t.Fatal(err)
	}
	return response.Result().Cookies()[0]
}

func TestLoadConfigAcceptsPasswordSaltAsPepper(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{"PASSWORD_SALT":"legacy-pepper","WEBAUTHN_RP_ID":"example.com","WEBAUTHN_RP_ORIGINS":["https://example.com"]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	config, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if config.AdminPasswordPepper != "legacy-pepper" || config.WebAuthnRPID != "example.com" || len(config.WebAuthnRPOrigins) != 1 {
		t.Fatalf("loaded config = %#v", config)
	}
}

func TestLoadConfigRejectsTrailingJSON(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{} {}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadConfig(path); err == nil {
		t.Fatal("LoadConfig() accepted trailing JSON")
	}
}

func TestLoadConfigRejectsUnknownFields(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{"ADMIN_PASSWORD_HAS":"typo"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadConfig(path); err == nil {
		t.Fatal("LoadConfig() accepted an unknown field")
	}
}

var _ fs.FS = fstest.MapFS{}

type appPasteAPI struct {
	mu   sync.Mutex
	gist paste.Gist
}

func (api *appPasteAPI) List(context.Context, int, int) ([]paste.Gist, bool, error) {
	api.mu.Lock()
	defer api.mu.Unlock()
	if api.gist.ID == "" {
		return nil, false, nil
	}
	return []paste.Gist{api.gist}, false, nil
}

func (api *appPasteAPI) Get(_ context.Context, id string) (paste.Gist, error) {
	api.mu.Lock()
	defer api.mu.Unlock()
	if api.gist.ID == "" || api.gist.ID != id {
		return paste.Gist{}, &paste.GistError{Kind: paste.GistNotFound, Message: "not found"}
	}
	return api.gist, nil
}

func (api *appPasteAPI) Create(_ context.Context, input paste.GistCreate) (paste.Gist, error) {
	api.mu.Lock()
	defer api.mu.Unlock()
	file := input.Files[paste.GistFilename]
	api.gist = paste.Gist{
		ID: "abcdef", Description: input.Description, CreatedAt: "2026-01-01T00:00:00Z", UpdatedAt: "2026-01-01T00:00:00Z",
		Files:   map[string]paste.GistFile{paste.GistFilename: {Filename: paste.GistFilename, Content: file.Content}},
		History: []paste.GistHistory{{Version: "01"}},
	}
	return api.gist, nil
}

func (api *appPasteAPI) Update(_ context.Context, id string, input paste.GistUpdate) (paste.Gist, error) {
	api.mu.Lock()
	defer api.mu.Unlock()
	file := input.Files[paste.GistFilename]
	api.gist.Files[paste.GistFilename] = paste.GistFile{Filename: paste.GistFilename, Content: file.Content}
	revision := "02"
	if api.gist.History[0].Version == "02" {
		revision = "03"
	}
	api.gist.History = []paste.GistHistory{{Version: revision}}
	return api.gist, nil
}

func (api *appPasteAPI) Delete(_ context.Context, id string) error {
	api.mu.Lock()
	defer api.mu.Unlock()
	api.gist = paste.Gist{}
	return nil
}

func TestAdminPasteCRUDRotationAndProtection(t *testing.T) {
	application := newTestApp(t)
	api := &appPasteAPI{}
	codec, err := paste.NewCodec(paste.Secrets{
		GitHubGistToken: "token", ActiveKeyID: "key-1",
		Keys: []paste.KeyConfig{{ID: "key-1", KeyHex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	application.pastes, err = paste.NewStore(api, codec, 1024, 20)
	if err != nil {
		t.Fatal(err)
	}
	application.config.PasteMaxBodyBytes = 1024

	protected := httptest.NewRecorder()
	application.ServeHTTP(protected, httptest.NewRequest(http.MethodGet, "/admin/pastes", nil))
	if protected.Code != http.StatusSeeOther || protected.Header().Get("Location") != "/admin/login" {
		t.Fatalf("protected = %d %q", protected.Code, protected.Header().Get("Location"))
	}
	cookie := adminCookie(t, application)

	create := httptest.NewRequest(http.MethodPost, "/admin/pastes/new", strings.NewReader(url.Values{"title": {"Secret title"}, "body": {"plain secret"}}.Encode()))
	create.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	create.AddCookie(cookie)
	createResponse := httptest.NewRecorder()
	application.ServeHTTP(createResponse, create)
	if createResponse.Code != http.StatusSeeOther || createResponse.Header().Get("Location") != "/admin/pastes/abcdef?notice=created" {
		t.Fatalf("create = %d %q: %s", createResponse.Code, createResponse.Header().Get("Location"), createResponse.Body.String())
	}
	if strings.Contains(api.gist.Files[paste.GistFilename].Content, "plain secret") {
		t.Fatal("remote Gist contains plaintext")
	}

	edit := httptest.NewRequest(http.MethodGet, "/admin/pastes/abcdef", nil)
	edit.AddCookie(cookie)
	editResponse := httptest.NewRecorder()
	application.ServeHTTP(editResponse, edit)
	if editResponse.Code != http.StatusOK || !strings.Contains(editResponse.Body.String(), "plain secret") ||
		!strings.Contains(editResponse.Body.String(), `action="/admin/pastes/abcdef"`) ||
		!strings.Contains(editResponse.Body.String(), `name="revision" value="01" formaction="/admin/pastes/abcdef"`) ||
		!strings.Contains(editResponse.Body.String(), `formaction="/admin/pastes/abcdef/rotate"`) ||
		strings.Contains(editResponse.Body.String(), `type="hidden"`) || editResponse.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("edit = %d: %s", editResponse.Code, editResponse.Body.String())
	}

	conflict := httptest.NewRequest(http.MethodPost, "/admin/pastes/abcdef", strings.NewReader(url.Values{"revision": {"ff"}, "title": {"Changed"}, "body": {"changed"}}.Encode()))
	conflict.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	conflict.AddCookie(cookie)
	conflictResponse := httptest.NewRecorder()
	application.ServeHTTP(conflictResponse, conflict)
	if conflictResponse.Code != http.StatusConflict || !strings.Contains(conflictResponse.Body.String(), "remote revision changed") {
		t.Fatalf("conflict = %d: %s", conflictResponse.Code, conflictResponse.Body.String())
	}

	save := httptest.NewRequest(http.MethodPost, "/admin/pastes/abcdef", strings.NewReader(url.Values{"revision": {"01"}, "title": {"Changed"}, "body": {"changed"}}.Encode()))
	save.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	save.AddCookie(cookie)
	saveResponse := httptest.NewRecorder()
	application.ServeHTTP(saveResponse, save)
	if saveResponse.Code != http.StatusSeeOther {
		t.Fatalf("save = %d: %s", saveResponse.Code, saveResponse.Body.String())
	}

	rotate := httptest.NewRequest(http.MethodPost, "/admin/pastes/abcdef/rotate", strings.NewReader("revision=02"))
	rotate.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rotate.AddCookie(cookie)
	rotateResponse := httptest.NewRecorder()
	application.ServeHTTP(rotateResponse, rotate)
	if rotateResponse.Code != http.StatusSeeOther {
		t.Fatalf("rotate = %d: %s", rotateResponse.Code, rotateResponse.Body.String())
	}

	remove := httptest.NewRequest(http.MethodPost, "/admin/pastes/abcdef/delete", strings.NewReader("revision=03&confirmation=DELETE"))
	remove.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	remove.AddCookie(cookie)
	removeResponse := httptest.NewRecorder()
	application.ServeHTTP(removeResponse, remove)
	if removeResponse.Code != http.StatusSeeOther || removeResponse.Header().Get("Location") != "/admin/pastes?notice=deleted" {
		t.Fatalf("delete = %d %q", removeResponse.Code, removeResponse.Header().Get("Location"))
	}
}
