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
	result, started := app.startProjectsRefresh()
	if !isDatastarRequest(request) {
		http.Redirect(writer, request, "/admin", http.StatusSeeOther)
		return
	}

	writer.Header().Add("Vary", "Accept")
	writer.Header().Add("Vary", "Datastar-Request")
	writer.Header().Add("Vary", "Accept-Encoding")
	sse := datastar.NewSSE(writer, request, datastar.WithCompression())
	if !started {
		_ = sse.PatchElementTempl(web.ProjectRefreshStatus("Un rafraîchissement est déjà en cours.", false))
		return
	}
	if err := sse.PatchElementTempl(web.ProjectRefreshStatus("Rafraîchissement des projets en cours…", false)); err != nil {
		return
	}

	select {
	case err := <-result:
		if err != nil {
			_ = sse.PatchElementTempl(web.ProjectRefreshStatus("Échec du rafraîchissement des projets.", true))
			return
		}
		_ = sse.PatchElementTempl(web.ProjectRefreshStatus("Projets rafraîchis avec succès.", false))
	case <-request.Context().Done():
	}
}

func (app *App) startProjectsRefresh() (<-chan error, bool) {
	select {
	case app.projectsRefresh <- struct{}{}:
		result := make(chan error, 1)
		go func() {
			defer func() { <-app.projectsRefresh }()
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			defer cancel()
			err := app.projects.Refresh(ctx)
			if err != nil {
				slog.Warn("projects cache refresh failed", "error", err)
			}
			result <- err
			close(result)
		}()
		return result, true
	default:
		return nil, false
	}
}
