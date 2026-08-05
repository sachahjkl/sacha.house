package app

import (
	"context"
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
	ctx, cancel := context.WithTimeout(request.Context(), 30*time.Second)
	defer cancel()
	if err := app.projects.Refresh(ctx); err != nil {
		app.renderAdminPage(writer, request, "Failed to refresh projects.", http.StatusUnprocessableEntity)
		return
	}
	http.Redirect(writer, request, "/admin", http.StatusSeeOther)
}
