package app

import (
	"net/http"
	"strconv"

	"sacha.house/internal/paste"
	"sacha.house/internal/web"
)

func (app *App) adminPastes(writer http.ResponseWriter, request *http.Request) {
	writer.Header().Set("Cache-Control", "no-store")
	data := web.AdminPastesPageData{
		PageData: app.page(request.URL.Path, "encrypted pastes / admin / sacha.house", "Manage encrypted GitHub Gist pastes."),
		Notice:   pasteNotice(request.URL.Query().Get("notice")),
	}
	if app.pastes == nil {
		data.Error = "Encrypted pastes are disabled. Set PASTE_ENABLED and PASTE_SECRETS_FILE."
		app.renderPage(writer, request, web.AdminPastesPage(data, navigation(request, http.StatusServiceUnavailable)), http.StatusServiceUnavailable)
		return
	}
	summaries, truncated, err := app.pastes.List(request.Context())
	data.Truncated = truncated
	data.Items = make([]web.AdminPasteListItem, len(summaries))
	for index, summary := range summaries {
		canEdit := summary.Status == paste.StatusReady || summary.Status == paste.StatusNeedsRotation
		data.Items[index] = web.AdminPasteListItem{
			GistID: summary.GistID, Revision: summary.Revision, KeyID: summary.KeyID, PasteID: summary.PasteID,
			Title: summary.Title, CreatedAt: summary.CreatedAt, UpdatedAt: summary.UpdatedAt,
			Status: summary.Status.String(), CanEdit: canEdit, NeedsRotation: summary.Status == paste.StatusNeedsRotation,
		}
	}
	if err != nil {
		data.Error = err.Error()
		data.Truncated = true
		setPasteRetryAfter(writer, err)
	}
	app.renderPage(writer, request, web.AdminPastesPage(data, navigation(request, http.StatusOK)), http.StatusOK)
}

func (app *App) adminNewPaste(writer http.ResponseWriter, request *http.Request) {
	if app.pastes == nil {
		http.NotFound(writer, request)
		return
	}
	app.renderPasteEditor(writer, request, web.PasteForm{FormAction: "/admin/pastes/new", IsNew: true}, "", "", http.StatusOK)
}

func (app *App) adminEditPaste(writer http.ResponseWriter, request *http.Request) {
	if app.pastes == nil || !paste.ValidateGistID(request.PathValue("id")) {
		http.NotFound(writer, request)
		return
	}
	loaded, err := app.pastes.Get(request.Context(), request.PathValue("id"))
	if err != nil {
		if kind := paste.ErrorKindOf(err); kind == paste.ErrorNotFound || kind == paste.ErrorNotOurs {
			http.NotFound(writer, request)
			return
		}
		setPasteRetryAfter(writer, err)
		form := web.PasteForm{GistID: request.PathValue("id"), FormAction: "/admin/pastes/" + request.PathValue("id")}
		app.renderPasteEditor(writer, request, form, err.Error(), "", pasteStatus(err, false))
		return
	}
	app.renderPasteEditor(writer, request, pasteForm(loaded), "", pasteNotice(request.URL.Query().Get("notice")), http.StatusOK)
}

func (app *App) adminCreatePaste(writer http.ResponseWriter, request *http.Request) {
	if app.pastes == nil {
		http.NotFound(writer, request)
		return
	}
	form, ok := app.parsePasteForm(writer, request, true)
	if !ok {
		return
	}
	loaded, err := app.pastes.Create(request.Context(), paste.Input{Title: form.Title, Body: form.Body}, app.options.Now().UnixMilli())
	if err != nil {
		setPasteRetryAfter(writer, err)
		message := err.Error()
		if paste.ErrorKindOf(err) == paste.ErrorOutcomeUnknown {
			message = "The remote create outcome is unknown. Refresh the paste list before trying again."
		}
		app.renderPasteEditor(writer, request, form, message, "", pasteStatus(err, true))
		return
	}
	http.Redirect(writer, request, "/admin/pastes/"+loaded.GistID+"?notice=created", http.StatusSeeOther)
}

func (app *App) adminSavePaste(writer http.ResponseWriter, request *http.Request) {
	if app.pastes == nil || !paste.ValidateGistID(request.PathValue("id")) {
		http.NotFound(writer, request)
		return
	}
	form, ok := app.parsePasteForm(writer, request, false)
	if !ok {
		return
	}
	if !paste.ValidateRevision(form.Revision) {
		app.renderPasteEditor(writer, request, form, "Invalid or missing paste revision.", "", http.StatusUnprocessableEntity)
		return
	}
	_, err := app.pastes.Update(request.Context(), form.GistID, form.Revision, paste.Input{Title: form.Title, Body: form.Body}, app.options.Now().UnixMilli())
	if err != nil {
		if kind := paste.ErrorKindOf(err); kind == paste.ErrorNotFound || kind == paste.ErrorNotOurs {
			http.NotFound(writer, request)
			return
		}
		setPasteRetryAfter(writer, err)
		app.renderPasteEditor(writer, request, form, err.Error(), "", pasteStatus(err, true))
		return
	}
	http.Redirect(writer, request, "/admin/pastes/"+form.GistID+"?notice=saved", http.StatusSeeOther)
}

func (app *App) adminRotatePaste(writer http.ResponseWriter, request *http.Request) {
	app.pasteRevisionMutation(writer, request, false)
}

func (app *App) adminDeletePaste(writer http.ResponseWriter, request *http.Request) {
	app.pasteRevisionMutation(writer, request, true)
}

func (app *App) pasteRevisionMutation(writer http.ResponseWriter, request *http.Request, deletePaste bool) {
	gistID := request.PathValue("id")
	if app.pastes == nil || !paste.ValidateGistID(gistID) {
		http.NotFound(writer, request)
		return
	}
	request.Body = http.MaxBytesReader(writer, request.Body, int64(app.config.PasteMaxBodyBytes*3+8192))
	if err := request.ParseForm(); err != nil {
		http.Error(writer, "invalid paste form", http.StatusBadRequest)
		return
	}
	revision := request.PostForm.Get("revision")
	if !paste.ValidateRevision(revision) || deletePaste && request.PostForm.Get("confirmation") != "DELETE" {
		http.Error(writer, "invalid paste mutation", http.StatusUnprocessableEntity)
		return
	}
	var err error
	if deletePaste {
		err = app.pastes.Delete(request.Context(), gistID, revision)
	} else {
		_, err = app.pastes.Rotate(request.Context(), gistID, revision)
	}
	if err != nil {
		if kind := paste.ErrorKindOf(err); kind == paste.ErrorNotFound || kind == paste.ErrorNotOurs {
			http.NotFound(writer, request)
			return
		}
		setPasteRetryAfter(writer, err)
		form := web.PasteForm{GistID: gistID, Revision: revision, FormAction: "/admin/pastes/" + gistID}
		app.renderPasteEditor(writer, request, form, err.Error(), "", pasteStatus(err, false))
		return
	}
	if deletePaste {
		http.Redirect(writer, request, "/admin/pastes?notice=deleted", http.StatusSeeOther)
		return
	}
	http.Redirect(writer, request, "/admin/pastes/"+gistID+"?notice=rotated", http.StatusSeeOther)
}

func (app *App) parsePasteForm(writer http.ResponseWriter, request *http.Request, isNew bool) (web.PasteForm, bool) {
	request.Body = http.MaxBytesReader(writer, request.Body, int64(app.config.PasteMaxBodyBytes*3+8192))
	if err := request.ParseForm(); err != nil {
		form := web.PasteForm{IsNew: isNew, FormAction: request.URL.Path, GistID: request.PathValue("id")}
		app.renderPasteEditor(writer, request, form, "Paste form exceeds the allowed size.", "", http.StatusRequestEntityTooLarge)
		return form, false
	}
	form := web.PasteForm{
		GistID: request.PathValue("id"), Revision: request.PostForm.Get("revision"), Title: request.PostForm.Get("title"), Body: request.PostForm.Get("body"),
		FormAction: request.URL.Path, IsNew: isNew,
	}
	if err := app.pastes.Validate(paste.Input{Title: form.Title, Body: form.Body}, app.options.Now().UnixMilli()); err != nil {
		app.renderPasteEditor(writer, request, form, err.Error(), "", pasteStatus(err, true))
		return form, false
	}
	return form, true
}

func (app *App) renderPasteEditor(writer http.ResponseWriter, request *http.Request, form web.PasteForm, message, notice string, status int) {
	writer.Header().Set("Cache-Control", "no-store")
	data := web.AdminPasteEditorPageData{
		PageData: app.page(request.URL.Path, "encrypted paste editor / admin / sacha.house", "Admin encrypted paste editor."),
		Form:     form, Error: message, Notice: notice,
	}
	app.renderPage(writer, request, web.AdminPasteEditorPage(data, navigation(request, status)), status)
}

func pasteForm(loaded paste.Loaded) web.PasteForm {
	return web.PasteForm{
		GistID: loaded.GistID, Revision: loaded.Revision, Title: loaded.Document.Title, Body: loaded.Document.Body,
		KeyID: loaded.KeyID, FormAction: "/admin/pastes/" + loaded.GistID, NeedsRotation: loaded.NeedsRotation,
	}
}

func pasteNotice(value string) string {
	switch value {
	case "created":
		return "Encrypted paste created."
	case "saved":
		return "Encrypted paste saved."
	case "rotated":
		return "Encrypted paste re-encrypted with the active key."
	case "deleted":
		return "Encrypted paste deleted."
	default:
		return ""
	}
}

func pasteStatus(err error, clientInput bool) int {
	switch paste.ErrorKindOf(err) {
	case paste.ErrorNotFound, paste.ErrorNotOurs:
		return http.StatusNotFound
	case paste.ErrorInvalidInput, paste.ErrorUnknownKey, paste.ErrorCorrupt:
		return http.StatusUnprocessableEntity
	case paste.ErrorConflict:
		return http.StatusConflict
	case paste.ErrorRateLimited:
		return http.StatusTooManyRequests
	case paste.ErrorTooLarge:
		if clientInput {
			return http.StatusRequestEntityTooLarge
		}
		return http.StatusBadGateway
	case paste.ErrorOutcomeUnknown:
		return http.StatusBadGateway
	default:
		return http.StatusServiceUnavailable
	}
}

func setPasteRetryAfter(writer http.ResponseWriter, err error) {
	if seconds := paste.RetryAfterSeconds(err); seconds > 0 {
		writer.Header().Set("Retry-After", strconv.Itoa(seconds))
	}
}
