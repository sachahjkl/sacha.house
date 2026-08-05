package app

import (
	"crypto/rand"
	"fmt"
	"io"
	"net/http"

	"sacha.house/internal/projects"
	"sacha.house/internal/web"
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
	data := web.HomePageData{
		PageData: app.page(request.URL.Path, "home / sacha.house", web.Me.FullName+"'s personal website."),
		Mail:     web.Me.Mail, CV: web.Me.CurriculumVitae,
	}
	app.renderPage(writer, request, web.HomePage(data, navigation(request, http.StatusOK)), http.StatusOK)
}

func (app *App) about(writer http.ResponseWriter, request *http.Request) {
	identity := web.Me
	data := web.AboutPageData{
		PageData: app.page(request.URL.Path, "about / sacha.house", "Presentation of Sacha Froment and his contact details."),
		Identity: identity, Age: identity.AgeAt(app.options.Now()),
		LinkedInExperiences: app.profile.Experiences, LinkedInEducation: app.profile.Education,
	}
	app.renderPage(writer, request, web.AboutPage(data, navigation(request, http.StatusOK)), http.StatusOK)
}

func (app *App) projectsPage(writer http.ResponseWriter, request *http.Request) {
	cache := app.projects.Get()
	data := web.ProjectsPageData{
		PageData: app.page(request.URL.Path, "projects / sacha.house", "My personal projects."),
		Identity: web.Me, GitLabProjects: projectViews(cache.GitLab), GitHubProjects: projectViews(cache.GitHub),
	}
	app.renderPage(writer, request, web.ProjectsPage(data, navigation(request, http.StatusOK)), http.StatusOK)
}

func projectViews(input []projects.Project) []web.ProjectView {
	views := make([]web.ProjectView, len(input))
	for index, project := range input {
		views[index] = web.ProjectView{
			Name: project.Name, URL: project.URL, DescriptionHTML: project.DescriptionHTML,
			AvatarURL: project.AvatarURL, HasAvatar: project.HasAvatar,
			HSLColor: project.HSLColor, FirstLetter: project.FirstLetter,
		}
	}
	return views
}

func (app *App) teapot(writer http.ResponseWriter, request *http.Request) {
	data := web.TeapotPageData{PageData: app.page(request.URL.Path, "teapot / sacha.house", "I'm a teapot."), Spewage: randomString(5)}
	status := http.StatusOK
	switch request.URL.Query().Get("drink") {
	case "tea":
		data.BrewMessage = web.BrewMessage{Text: "Here is your tea!", Emoji: "🍵"}
	case "coffee":
		status = http.StatusTeapot
		data.IsATeapot = true
		data.BrewMessage.Text = "Did you really think a teapot could brew you coffee ??\nare you some kind of lunatic or something ?"
	case "":
	default:
		data.BrewMessage = web.BrewMessage{Text: fmt.Sprintf("What kind of a drink is %q ???", request.URL.Query().Get("drink")), Emoji: "🤮"}
	}
	app.renderPage(writer, request, web.TeapotPage(data, navigation(request, status)), status)
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
