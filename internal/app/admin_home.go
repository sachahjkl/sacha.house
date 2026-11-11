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
		BlogConflicts: app.blogConflictCount(),
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
	writer.Header().Set("X-Accel-Buffering", "no")
	sse := datastar.NewSSE(writer, request)
	if !started {
		_ = sse.PatchElementTempl(web.ProjectRefreshStatus("A refresh is already running.", ""))
		return
	}
	if err := sse.PatchElementTempl(web.ProjectRefreshStatus("Refreshing projects…", "")); err != nil {
		return
	}

	select {
	case err := <-result:
		if err != nil {
			_ = sse.PatchElementTempl(web.ProjectRefreshStatus("Could not refresh the projects.", "status-error"))
			return
		}
		_ = sse.PatchElementTempl(web.ProjectRefreshStatus("Projects refreshed.", "status-ok"))
	case <-request.Context().Done():
	}
}

// projectsRetryInterval spaces the refreshes a stale cache starts by itself, so a failing GitHub is not hammered.
const projectsRetryInterval = 10 * time.Minute

// refreshStaleProjects starts a background refresh when the pages that show projects find the cache stale. The
// server can run for weeks, and a refresh that failed at start must be tried again.
func (app *App) refreshStaleProjects() {
	now := app.options.Now()
	if !app.projects.Stale(now, projectsCacheMaxAge) {
		return
	}
	last := app.projectsAttempt.Load()
	if now.Sub(time.Unix(0, last)) < projectsRetryInterval || !app.projectsAttempt.CompareAndSwap(last, now.UnixNano()) {
		return
	}
	_, _ = app.startProjectsRefresh()
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
