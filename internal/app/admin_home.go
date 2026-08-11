package app

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/starfederation/datastar-go/datastar"

	"sacha.house/internal/web"
)

func (app *App) adminPage(writer http.ResponseWriter, request *http.Request) {
	app.renderAdminPage(writer, request, "", http.StatusOK)
}

func (app *App) renderAdminPage(writer http.ResponseWriter, request *http.Request, message string, status int) {
	data := web.AdminPageData{
		PageData:  app.page(request.URL.Path, "admin / sacha.house", "Administration panel."),
		IPAddress: app.requestIP(request), Error: message, PasteEnabled: app.pastes != nil,
	}
	renderHTML(writer, request, web.AdminPage(data), status)
}

func (app *App) adminRefreshProjects(writer http.ResponseWriter, request *http.Request) {
	started := app.startProjectsRefresh()
	if isDatastarRequest(request) {
		message := "Project refresh is already running."
		if started {
			message = "Project refresh started."
		}
		writer.Header().Add("Vary", "Accept")
		writer.Header().Add("Vary", "Datastar-Request")
		writer.Header().Add("Vary", "Accept-Encoding")
		sse := datastar.NewSSE(writer, request, datastar.WithCompression())
		_ = sse.PatchElementTempl(web.ProjectRefreshStatus(message))
		return
	}
	http.Redirect(writer, request, "/admin", http.StatusSeeOther)
}

func (app *App) startProjectsRefresh() bool {
	select {
	case app.projectsRefresh <- struct{}{}:
		go func() {
			defer func() { <-app.projectsRefresh }()
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			defer cancel()
			if err := app.projects.Refresh(ctx); err != nil {
				slog.Warn("projects cache refresh failed", "error", err)
			}
		}()
		return true
	default:
		return false
	}
}
