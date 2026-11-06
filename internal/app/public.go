package app

import (
	"crypto/rand"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"time"

	"sacha.house/internal/blog"
	"sacha.house/internal/projects"
	"sacha.house/internal/web"
)

const (
	homeProjects = 4
	homePosts    = 3
)

func (app *App) page(pathname, title, description string) web.PageData {
	styleVersion := ""
	if app.options.Development {
		styleVersion = app.bootID
	}
	return web.NewPageData(web.PageOptions{
		ActivePathname: pathname,
		SEO:            web.SEO{Title: title, Description: description},
		CommitHash:     app.options.CommitHash, GitRepoID: app.config.GitRepoID,
		Version: app.options.Version, StyleVersion: styleVersion, HotReload: app.options.Development,
		Now: app.options.Now(),
	})
}

func (app *App) home(writer http.ResponseWriter, request *http.Request) {
	all := projectViews(app.projects.Get().Projects)
	featured, _ := web.SplitProjects(all)
	data := web.HomePageData{
		PageData: app.page(request.URL.Path, web.Me.FullName+" / sacha.house", web.Me.FullName+", software engineer. Projects, writing, and how to reach me."),
		Mail:     web.Me.Mail, CV: web.Me.CurriculumVitae, Resume: "/resume",
		Projects: featured[:min(len(featured), homeProjects)], ProjectCount: len(all),
		Posts: app.latestPosts(homePosts),
	}
	renderHTML(writer, request, web.HomePage(data), http.StatusOK)
}

// latestPosts returns the most recent published posts. The home page stays up without them.
func (app *App) latestPosts(limit int) []web.PostView {
	posts, err := app.blog.List(false)
	if err != nil {
		return nil
	}
	views := make([]web.PostView, 0, limit)
	for _, metadata := range posts[:min(len(posts), limit)] {
		view := metadataView(metadata)
		if document, err := app.blog.Load(metadata.Slug, false); err == nil {
			view.Excerpt = blog.Excerpt(document.Markdown, blog.ExcerptLength)
		}
		views = append(views, view)
	}
	return views
}

// notFound is the HTML 404 of the public site.
func (app *App) notFound(writer http.ResponseWriter, request *http.Request) {
	page := app.page("/404", "not found / sacha.house", "This page does not exist.")
	page.SEO.NoIndex = true
	data := web.NotFoundPageData{PageData: page, Path: request.URL.Path}
	renderHTML(writer, request, web.NotFoundPage(data), http.StatusNotFound)
}

func (app *App) careerPage(writer http.ResponseWriter, request *http.Request, full bool) {
	language := "fr"
	if request.URL.Query().Get("lang") == "en" {
		language = "en"
	}
	profile := web.Career(language)
	documentName := profile.ResumeLabel
	if full {
		documentName = profile.CVLabel
	}
	page := app.page(request.URL.Path, documentName+" · "+web.Me.FullName, profile.Summary)
	page.Language = language
	data := web.CareerPageData{
		PageData: page, Identity: web.Me, Age: web.Me.AgeAt(app.options.Now()), Full: full, Profile: profile,
	}
	renderHTML(writer, request, web.CareerPage(data), http.StatusOK)
}

func (app *App) resume(writer http.ResponseWriter, request *http.Request) {
	app.careerPage(writer, request, false)
}

func (app *App) curriculumVitae(writer http.ResponseWriter, request *http.Request) {
	app.careerPage(writer, request, true)
}

func (app *App) legacyCurriculumVitae(writer http.ResponseWriter, request *http.Request) {
	http.Redirect(writer, request, "/cv", http.StatusMovedPermanently)
}

func (app *App) about(writer http.ResponseWriter, request *http.Request) {
	identity := web.Me
	data := web.AboutPageData{
		PageData: app.page(request.URL.Path, "about / sacha.house", "Who I am, where I have worked, and how to reach me."),
		Identity: identity, Age: identity.AgeAt(app.options.Now()), Career: web.Career("en"),
	}
	renderHTML(writer, request, web.AboutPage(data), http.StatusOK)
}

func (app *App) projectsPage(writer http.ResponseWriter, request *http.Request) {
	featured, others := web.SplitProjects(projectViews(app.projects.Get().Projects))
	data := web.ProjectsPageData{
		PageData: app.page(request.URL.Path, "projects / sacha.house", "What I build: a web browser, a GUI toolkit, native clients, and everything else on my GitHub."),
		Identity: web.Me, Featured: featured, Others: others,
	}
	renderHTML(writer, request, web.ProjectsPage(data), http.StatusOK)
}

func projectViews(input []projects.Project) []web.ProjectView {
	views := make([]web.ProjectView, len(input))
	for index, project := range input {
		views[index] = web.ProjectView{
			Name: project.Name, URL: project.URL, DescriptionHTML: project.DescriptionHTML,
			AvatarURL: project.AvatarURL, HasAvatar: project.HasAvatar,
			HSLColor: project.HSLColor, FirstLetter: project.FirstLetter,
			LastCommitDate: project.LastCommitDate.Format("2006-01-02"),
			LastCommitTime: project.LastCommitDate.Format(time.RFC3339),
			LastCommitHash: project.LastCommitHash, LastCommitURL: project.LastCommitURL,
			LicenseLabel: projects.LicenseLabel(project.LicenseSPDXID, project.LicenseName, project.LicenseTitle), LicenseURL: project.LicenseURL,
		}
	}
	return views
}

func (app *App) teapot(writer http.ResponseWriter, request *http.Request) {
	data := web.TeapotPageData{PageData: app.page(request.URL.Path, "teapot / sacha.house", "I'm a teapot."), Spewage: randomString(5)}
	status := http.StatusOK
	switch request.URL.Query().Get("drink") {
	case "tea":
		data.BrewMessage = web.BrewMessage{Text: "Here is your tea!", Emoji: "teacup-without-handle"}
	case "coffee":
		status = http.StatusTeapot
		data.IsATeapot = true
		data.BrewMessage.Text = "Did you really think a teapot could brew you coffee ??\nare you some kind of lunatic or something ?"
	case "":
	default:
		data.BrewMessage = web.BrewMessage{Text: fmt.Sprintf("What kind of a drink is %q ???", request.URL.Query().Get("drink")), Emoji: "nauseated-face"}
	}
	renderHTML(writer, request, web.TeapotPage(data), status)
}

// publicKeys are the key files shown on the key pages, by page path.
var publicKeys = map[string]struct{ id, heading, file string }{
	"/ssh": {"ssh-key", "ssh public key", "sachahjkl.pub"},
	"/gpg": {"gpg-key", "pgp public key", "sachahjkl.gpg"},
}

// keyPage shows one or several public keys as a regular HTML page, so that
// every browser displays them instead of offering to download them.
func (app *App) keyPage(heading, description string, paths ...string) http.HandlerFunc {
	return func(writer http.ResponseWriter, request *http.Request) {
		keys := make([]web.KeyView, 0, len(paths))
		for _, path := range paths {
			source := publicKeys[path]
			content, err := fs.ReadFile(app.static, source.file)
			if err != nil {
				app.notFound(writer, request)
				return
			}
			keys = append(keys, web.KeyView{
				ID: source.id, Heading: source.heading, Key: string(content),
				Path: path, RawPath: "/" + source.file,
			})
		}
		data := web.KeyPageData{
			PageData: app.page(request.URL.Path, heading+" / sacha.house", description),
			Heading:  heading, Description: description, Keys: keys,
		}
		renderHTML(writer, request, web.KeyPage(data), http.StatusOK)
	}
}

func randomString(length int) string {
	const alphabet = "abcdefghijklmnopqrstuvwxyz1234567890"
	value := make([]byte, length)
	if _, err := rand.Read(value); err != nil {
		panic(err)
	}
	for index := range value {
		value[index] = alphabet[int(value[index])%len(alphabet)]
	}
	return string(value)
}

func (app *App) ping(writer http.ResponseWriter, _ *http.Request) {
	if app.options.Development {
		writer.Header().Set("Cache-Control", "no-store")
		writer.Header().Set("X-Dev-Server-Boot", app.bootID)
	}
	writer.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = io.WriteString(writer, "pong")
}

func (app *App) ip(writer http.ResponseWriter, request *http.Request) {
	writer.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = io.WriteString(writer, app.requestIP(request))
}

func (app *App) mariage(writer http.ResponseWriter, request *http.Request) {
	http.Redirect(writer, request, "/static/Patricia_et_Sacha_Invitation.pdf", http.StatusFound)
}
