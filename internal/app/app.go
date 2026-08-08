package app

import (
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"sacha.house/internal/auth"
	"sacha.house/internal/blog"
	"sacha.house/internal/paste"
	"sacha.house/internal/projects"
	"sacha.house/internal/web"
	staticassets "sacha.house/internal/web/static"
)

const (
	defaultBlogRoot     = "data/blog"
	defaultProjectsPath = "projects_cache.json"
	publicCache         = "public, max-age=86400"
	feedCache           = "public, max-age=600"
	projectsCacheMaxAge = 24 * time.Hour
)

type Options struct {
	BlogRoot        string
	ProjectsPath    string
	ProjectsFetcher projects.Fetcher
	StaticFS        fs.FS
	Version         string
	CommitHash      string
	Development     bool
	Now             func() time.Time
	PasteGistAPI    paste.GistAPI
}

type App struct {
	handler         http.Handler
	auth            *auth.Store
	blog            *blog.Store
	passkeys        *auth.PasskeyStore
	pastes          *paste.Store
	projects        *projects.Store
	profile         web.LinkedInProfile
	static          fs.FS
	config          Config
	options         Options
	passwordChecks  chan struct{}
	projectsRefresh chan struct{}
	bootID          string
}

func NewWithOptions(config Config, options Options) (*App, error) {
	var err error
	config, err = normalizeConfig(config)
	if err != nil {
		return nil, err
	}
	if config.AdminPasswordHash != "" {
		if config.AdminPasswordPepper == "" {
			return nil, errors.New("ADMIN_PASSWORD_PEPPER must be set when ADMIN_PASSWORD_HASH is set")
		}
		if err := auth.ValidatePasswordHash(config.AdminPasswordHash); err != nil {
			return nil, fmt.Errorf("ADMIN_PASSWORD_HASH is invalid: %w", err)
		}
	}
	if options.BlogRoot == "" {
		options.BlogRoot = defaultBlogRoot
	}
	if options.ProjectsPath == "" {
		options.ProjectsPath = defaultProjectsPath
	}
	if options.StaticFS == nil {
		options.StaticFS = staticassets.Files
	}
	if options.Now == nil {
		options.Now = time.Now
	}

	blogStore, err := blog.NewStore(options.BlogRoot, web.Me.FullName)
	if err != nil {
		return nil, err
	}

	fetcher := options.ProjectsFetcher
	if fetcher == nil {
		fetcher = projects.NewClient(&http.Client{Timeout: 20 * time.Second}, projects.ClientConfig{
			GitHubEndpoint: config.GitHubGraphQLAPIEndpoint,
			GitHubToken:    config.GitHubBearerToken,
			Username:       web.Me.Username,
		})
	}
	projectStore := projects.NewStore(options.ProjectsPath, fetcher)
	loadErr := projectStore.Load()
	if loadErr != nil && !errors.Is(loadErr, fs.ErrNotExist) {
		slog.Warn("projects cache is invalid", "error", loadErr)
	}
	refreshProjects := loadErr != nil || projectStore.Stale(options.Now(), projectsCacheMaxAge)

	profile, err := (web.FSLinkedInProfileLoader{FS: options.StaticFS, Path: "linkedin_profile.json"}).Load()
	if err != nil {
		return nil, err
	}
	cookie := auth.DefaultCookieConfig()
	cookie.Secure = !options.Development
	cookie.SameSite = http.SameSiteStrictMode
	authStore := auth.NewStore(auth.Config{Now: options.Now, Cookie: cookie})
	rpID := config.WebAuthnRPID
	origins := append([]string(nil), config.WebAuthnRPOrigins...)
	if rpID == "" {
		if options.Development {
			rpID = "localhost"
		} else {
			rpID = "sacha.house"
		}
	}
	if len(origins) == 0 {
		if options.Development {
			origins = []string{"http://localhost:6969", "http://localhost:3000"}
		} else {
			origins = []string{"https://sacha.house"}
		}
	}
	passkeys, err := auth.NewPasskeyStore(auth.PasskeyConfig{
		CredentialsFile: config.WebAuthnCredentialsFile,
		RPID:            rpID, RPDisplayName: "sacha.house Admin", RPOrigins: origins,
		AdminName: "admin", AdminDisplayName: "Administrator", Now: options.Now,
	})
	if err != nil {
		return nil, err
	}
	if config.AdminPasswordHash == "" && len(passkeys.List()) == 0 {
		return nil, errors.New("admin authentication requires a password hash or a registered passkey")
	}

	var pasteStore *paste.Store
	if config.PasteEnabled {
		secrets, err := paste.LoadSecrets(config.PasteSecretsFile)
		if err != nil {
			return nil, err
		}
		codec, err := paste.NewCodec(secrets)
		if err != nil {
			return nil, err
		}
		gistAPI := options.PasteGistAPI
		if gistAPI == nil {
			gistAPI, err = paste.NewGistClient(config.GitHubRESTAPIEndpoint, secrets.GitHubGistToken, &http.Client{Timeout: 20 * time.Second})
			if err != nil {
				return nil, err
			}
		}
		pasteStore, err = paste.NewStore(gistAPI, codec, config.PasteMaxBodyBytes, config.PasteMaxListItems)
		if err != nil {
			return nil, err
		}
	}

	application := &App{
		auth: authStore, blog: blogStore, passkeys: passkeys, pastes: pasteStore, projects: projectStore,
		profile: profile, static: options.StaticFS, config: config, options: options,
		passwordChecks:  make(chan struct{}, 2),
		projectsRefresh: make(chan struct{}, 1),
		bootID:          fmt.Sprintf("%d", options.Now().UnixNano()),
	}
	application.handler = application.routes()
	if refreshProjects {
		application.startProjectsRefresh()
	}
	return application, nil
}

func (app *App) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	app.handler.ServeHTTP(writer, request)
}

func (app *App) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", app.home)
	mux.HandleFunc("GET /blog", app.blogIndex)
	mux.HandleFunc("GET /blog/{slug}", app.blogPost)
	mux.HandleFunc("GET /blog/rss.xml", app.rss)
	mux.HandleFunc("GET /blog/atom.xml", app.atom)
	mux.HandleFunc("GET /about", app.about)
	mux.HandleFunc("GET /resume", app.resume)
	mux.HandleFunc("GET /cv", app.curriculumVitae)
	mux.HandleFunc("GET /cv.html", app.legacyCurriculumVitae)
	mux.HandleFunc("GET /projects", app.projectsPage)
	mux.HandleFunc("GET /teapot", app.teapot)
	mux.HandleFunc("GET /ping", app.ping)
	mux.HandleFunc("GET /ip", app.ip)
	mux.HandleFunc("GET /api/ip", app.ip)
	mux.HandleFunc("GET /mariage", app.mariage)
	mux.Handle("GET /static/{path...}", app.staticHandler())
	mux.HandleFunc("GET /media/blog/{slug}/assets/{path...}", app.blogMedia)
	mux.HandleFunc("GET /admin/login", app.adminLoginPage)
	mux.HandleFunc("POST /admin/login", app.adminLogin)
	mux.HandleFunc("POST /admin/logout", app.adminLogout)
	mux.HandleFunc("GET /admin/webauthn/login-challenge", app.webAuthnLoginChallenge)
	mux.HandleFunc("POST /admin/webauthn/login", app.webAuthnLogin)
	mux.Handle("GET /admin", app.requireAdmin(http.HandlerFunc(app.adminPage)))
	mux.Handle("GET /admin/blogposts", app.requireAdmin(http.HandlerFunc(app.adminBlogPosts)))
	mux.Handle("GET /admin/blogposts/new", app.requireAdmin(http.HandlerFunc(app.adminNewBlogPost)))
	mux.Handle("POST /admin/blogposts/new", app.requireAdmin(http.HandlerFunc(app.adminCreateBlogPost)))
	mux.Handle("GET /admin/blogposts/{slug}", app.requireAdmin(http.HandlerFunc(app.adminEditBlogPost)))
	mux.Handle("POST /admin/blogposts/{slug}/save", app.requireAdmin(http.HandlerFunc(app.adminSaveBlogPost)))
	mux.Handle("POST /admin/blogposts/upload-image", app.requireAdminAPI(http.HandlerFunc(app.adminUploadBlogImage)))
	mux.Handle("POST /admin/refresh-projects", app.requireAdmin(http.HandlerFunc(app.adminRefreshProjects)))
	mux.Handle("GET /admin/pastes", app.requireAdmin(http.HandlerFunc(app.adminPastes)))
	mux.Handle("GET /admin/pastes/new", app.requireAdmin(http.HandlerFunc(app.adminNewPaste)))
	mux.Handle("POST /admin/pastes/new", app.requireAdmin(http.HandlerFunc(app.adminCreatePaste)))
	mux.Handle("GET /admin/pastes/{id}", app.requireAdmin(http.HandlerFunc(app.adminEditPaste)))
	mux.Handle("POST /admin/pastes/{id}", app.requireAdmin(http.HandlerFunc(app.adminSavePaste)))
	mux.Handle("POST /admin/pastes/{id}/rotate", app.requireAdmin(http.HandlerFunc(app.adminRotatePaste)))
	mux.Handle("POST /admin/pastes/{id}/delete", app.requireAdmin(http.HandlerFunc(app.adminDeletePaste)))
	mux.Handle("GET /admin/webauthn", app.requireAdmin(http.HandlerFunc(app.adminWebAuthn)))
	mux.Handle("GET /admin/webauthn/passkeys", app.requireAdminAPI(http.HandlerFunc(app.adminPasskeys)))
	mux.Handle("GET /admin/webauthn/register-challenge", app.requireAdminAPI(http.HandlerFunc(app.webAuthnRegisterChallenge)))
	mux.Handle("POST /admin/webauthn/register", app.requireAdminAPI(http.HandlerFunc(app.webAuthnRegister)))
	mux.Handle("POST /admin/webauthn/remove", app.requireAdmin(http.HandlerFunc(app.webAuthnRemove)))
	mux.Handle("GET /{path...}", app.rootStaticHandler())
	csrf := http.NewCrossOriginProtection()
	return app.securityHeaders(csrf.Handler(mux))
}

func (app *App) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("X-Content-Type-Options", "nosniff")
		writer.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		writer.Header().Set("Permissions-Policy", "camera=(self), microphone=(), geolocation=()")
		if request.TLS != nil || app.config.TrustProxyHTTPS {
			writer.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		if strings.HasPrefix(request.URL.Path, "/admin") {
			writer.Header().Set("Cache-Control", "no-store")
		}
		next.ServeHTTP(writer, request)
	})
}
