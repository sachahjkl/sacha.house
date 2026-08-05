package app

import (
	"net/http"

	"sacha.house/internal/auth"
	"sacha.house/internal/web"
)

const (
	adminUserID      = "admin"
	maxAdminFormBody = 2 << 20
)

func (app *App) requireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		session, ok := app.auth.SessionFromRequest(request)
		if !ok || session.UserID != adminUserID {
			http.Redirect(writer, request, "/admin/login", http.StatusSeeOther)
			return
		}
		next.ServeHTTP(writer, request)
	})
}

func (app *App) requireAdminAPI(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		session, ok := app.auth.SessionFromRequest(request)
		if !ok || session.UserID != adminUserID {
			http.Error(writer, "admin authentication required", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(writer, request)
	})
}

func (app *App) adminLoginPage(writer http.ResponseWriter, request *http.Request) {
	if session, ok := app.auth.SessionFromRequest(request); ok && session.UserID == adminUserID {
		http.Redirect(writer, request, "/admin", http.StatusSeeOther)
		return
	}
	app.renderAdminLogin(writer, request, "", http.StatusOK)
}

func (app *App) adminLogin(writer http.ResponseWriter, request *http.Request) {
	client := app.requestIP(request)
	if !app.auth.AllowAttempt(client) {
		app.renderAdminLogin(writer, request, "Too many login attempts. Try again later.", http.StatusTooManyRequests)
		return
	}
	request.Body = http.MaxBytesReader(writer, request.Body, maxAdminFormBody)
	if err := request.ParseForm(); err != nil {
		app.auth.RecordFailure(client)
		app.renderAdminLogin(writer, request, "Invalid login form.", http.StatusUnprocessableEntity)
		return
	}
	password := request.PostForm.Get("password")
	select {
	case app.passwordChecks <- struct{}{}:
		defer func() { <-app.passwordChecks }()
	default:
		app.renderAdminLogin(writer, request, "Too many login attempts. Try again later.", http.StatusTooManyRequests)
		return
	}
	valid, err := auth.VerifyPassword(password, []byte(app.config.adminPasswordPepper()), app.config.AdminPasswordHash)
	if err != nil || !valid {
		app.auth.RecordFailure(client)
		app.renderAdminLogin(writer, request, "Invalid password.", http.StatusUnprocessableEntity)
		return
	}
	if _, err = app.auth.StartSession(writer, adminUserID); err != nil {
		http.Error(writer, "failed to start admin session", http.StatusInternalServerError)
		return
	}
	app.auth.ClearFailures(client)
	http.Redirect(writer, request, "/admin", http.StatusSeeOther)
}

func (app *App) renderAdminLogin(writer http.ResponseWriter, request *http.Request, message string, status int) {
	data := web.AdminLoginPageData{
		PageData:      app.page("/admin/login", "admin login / sacha.house", "Admin login."),
		LoginFormData: web.LoginFormData{Error: message},
	}
	app.renderPage(writer, request, web.AdminLoginPage(data, navigation(request, status)), status)
}

func (app *App) adminLogout(writer http.ResponseWriter, request *http.Request) {
	app.auth.Logout(writer, request)
	http.Redirect(writer, request, "/admin/login", http.StatusSeeOther)
}
