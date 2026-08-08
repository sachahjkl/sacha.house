package app

import (
	"context"
	"log/slog"
	"net/http"
	"time"

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
	app.renderPage(writer, request, web.AdminPage(data, navigation(request, status)), status)
}

func (app *App) adminRefreshProjects(writer http.ResponseWriter, request *http.Request) {
	app.startProjectsRefresh()
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
