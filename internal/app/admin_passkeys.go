package app

import (
	"net/http"
	"strings"
	"time"

	"github.com/starfederation/datastar-go/datastar"

	"sacha.house/internal/auth"
	"sacha.house/internal/web"
)

const maxWebAuthnBody = 1 << 20

func (app *App) adminWebAuthn(writer http.ResponseWriter, request *http.Request) {
	app.renderAdminWebAuthn(writer, request, "", http.StatusOK)
}

func (app *App) renderAdminWebAuthn(writer http.ResponseWriter, request *http.Request, message string, status int) {
	data := web.AdminWebAuthnPageData{
		PageData: app.page(request.URL.Path, "passkeys / admin / sacha.house", "Manage admin passkeys."),
		Passkeys: app.passkeyViews(), Error: message,
	}
	app.renderPage(writer, request, web.AdminWebAuthnPage(data, navigation(request, status)), status)
}

func (app *App) adminPasskeys(writer http.ResponseWriter, request *http.Request) {
	component := web.AdminPasskeyList(app.passkeyViews())
	if isDatastarRequest(request) {
		writer.Header().Add("Vary", "Accept")
		writer.Header().Add("Vary", "Datastar-Request")
		writer.Header().Add("Vary", "Accept-Encoding")
		sse := datastar.NewSSE(writer, request, datastar.WithCompression())
		_ = sse.PatchElementTempl(component, datastar.WithSelector("#passkey-list"))
		return
	}
	renderHTML(writer, request, component, http.StatusOK)
}

func (app *App) passkeyViews() []web.PasskeyView {
	passkeys := app.passkeys.List()
	views := make([]web.PasskeyView, len(passkeys))
	for index, passkey := range passkeys {
		views[index] = web.PasskeyView{ID: passkey.ID, Label: passkey.Label}
	}
	return views
}

func (app *App) webAuthnRegisterChallenge(writer http.ResponseWriter, request *http.Request) {
	label := strings.TrimSpace(request.URL.Query().Get("label"))
	if label == "" {
		label = "Passkey"
	}
	if len(label) > 80 {
		http.Error(writer, "passkey label exceeds 80 characters", http.StatusUnprocessableEntity)
		return
	}
	creation, token, err := app.passkeys.BeginRegistration(label)
	if err != nil {
		http.Error(writer, "failed to create registration challenge", http.StatusInternalServerError)
		return
	}
	app.setCeremonyCookie(writer, "webauthn_registration", token)
	writeJSON(writer, http.StatusOK, struct {
		PublicKey any `json:"publicKey"`
	}{PublicKey: creation.Response})
}

func (app *App) webAuthnRegister(writer http.ResponseWriter, request *http.Request) {
	token, ok := ceremonyToken(request, "webauthn_registration")
	if !ok {
		http.Error(writer, "registration challenge is missing", http.StatusUnprocessableEntity)
		return
	}
	request.Body = http.MaxBytesReader(writer, request.Body, maxWebAuthnBody)
	if _, err := app.passkeys.FinishRegistration(token, request); err != nil {
		http.Error(writer, "invalid passkey registration", http.StatusUnprocessableEntity)
		return
	}
	app.clearCeremonyCookie(writer, "webauthn_registration")
	writeJSON(writer, http.StatusOK, map[string]bool{"ok": true})
}

func (app *App) webAuthnLoginChallenge(writer http.ResponseWriter, request *http.Request) {
	client := app.requestIP(request)
	if !app.auth.AllowAttempt(client) {
		http.Error(writer, "too many login attempts", http.StatusTooManyRequests)
		return
	}
	if !app.auth.AllowChallenge(client) {
		http.Error(writer, "too many passkey challenges", http.StatusTooManyRequests)
		return
	}
	assertion, token, err := app.passkeys.BeginDiscoverableLogin()
	if err != nil {
		http.Error(writer, "failed to create login challenge", http.StatusInternalServerError)
		return
	}
	app.setCeremonyCookie(writer, "webauthn_login", token)
	writeJSON(writer, http.StatusOK, struct {
		PublicKey any `json:"publicKey"`
	}{PublicKey: assertion.Response})
}

func (app *App) webAuthnLogin(writer http.ResponseWriter, request *http.Request) {
	client := app.requestIP(request)
	if !app.auth.AllowAttempt(client) {
		http.Error(writer, "too many login attempts", http.StatusTooManyRequests)
		return
	}
	token, ok := ceremonyToken(request, "webauthn_login")
	if !ok {
		app.auth.RecordFailure(client)
		http.Error(writer, "login challenge is missing", http.StatusUnprocessableEntity)
		return
	}
	request.Body = http.MaxBytesReader(writer, request.Body, maxWebAuthnBody)
	if _, err := app.passkeys.FinishPasskeyLogin(token, request); err != nil {
		app.auth.RecordFailure(client)
		http.Error(writer, "invalid passkey login", http.StatusUnprocessableEntity)
		return
	}
	if _, err := app.auth.StartSession(writer, adminUserID); err != nil {
		http.Error(writer, "failed to start admin session", http.StatusInternalServerError)
		return
	}
	app.auth.ClearFailures(client)
	app.clearCeremonyCookie(writer, "webauthn_login")
	writeJSON(writer, http.StatusOK, map[string]bool{"ok": true})
}

func (app *App) webAuthnRemove(writer http.ResponseWriter, request *http.Request) {
	request.Body = http.MaxBytesReader(writer, request.Body, maxAdminFormBody)
	if err := request.ParseForm(); err != nil {
		app.renderAdminWebAuthn(writer, request, "Invalid remove form.", http.StatusUnprocessableEntity)
		return
	}
	var err error
	if app.config.AdminPasswordHash == "" {
		err = app.passkeys.RemoveUnlessLast(request.PostForm.Get("id"))
	} else {
		err = app.passkeys.Remove(request.PostForm.Get("id"))
	}
	if err != nil {
		app.renderAdminWebAuthn(writer, request, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	http.Redirect(writer, request, "/admin/webauthn", http.StatusSeeOther)
}

func (app *App) setCeremonyCookie(writer http.ResponseWriter, name, token string) {
	http.SetCookie(writer, &http.Cookie{
		Name: name, Value: token, Path: "/admin/webauthn", MaxAge: int(auth.PasskeyCeremonyLifetime.Seconds()),
		Expires: app.options.Now().Add(auth.PasskeyCeremonyLifetime), Secure: !app.options.Development,
		HttpOnly: true, SameSite: http.SameSiteStrictMode,
	})
}

func (app *App) clearCeremonyCookie(writer http.ResponseWriter, name string) {
	http.SetCookie(writer, &http.Cookie{
		Name: name, Path: "/admin/webauthn", MaxAge: -1, Expires: time.Unix(1, 0),
		Secure: !app.options.Development, HttpOnly: true, SameSite: http.SameSiteStrictMode,
	})
}

func ceremonyToken(request *http.Request, name string) (string, bool) {
	cookie, err := request.Cookie(name)
	if err != nil || cookie.Value == "" {
		return "", false
	}
	return cookie.Value, true
}
