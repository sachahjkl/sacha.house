package app

import (
	"bytes"
	"net/http"
	"strings"

	"github.com/a-h/templ"
	"github.com/starfederation/datastar-go/datastar"

	"sacha.house/internal/web"
)

func isDatastarRequest(request *http.Request) bool {
	if strings.EqualFold(strings.TrimSpace(request.Header.Get("Datastar-Request")), "true") {
		return true
	}
	for _, value := range strings.Split(request.Header.Get("Accept"), ",") {
		if strings.TrimSpace(strings.SplitN(value, ";", 2)[0]) == "text/event-stream" {
			return true
		}
	}
	return false
}

func navigation(request *http.Request, status int) web.Navigation {
	if !isDatastarRequest(request) {
		return web.Navigation{}
	}
	history := request.Header.Get("Datastar-History")
	if history == "" {
		history = request.Header.Get("Datastar-Navigation-History")
	}
	if history != "push" && history != "replace" && history != "none" && history != "true" && history != "false" {
		history = ""
	}
	navigationURL := *request.URL
	query := navigationURL.Query()
	query.Del("datastar")
	navigationURL.RawQuery = query.Encode()
	return web.Navigation{Enabled: true, URL: navigationURL.String(), Status: status, History: history}
}

func (app *App) renderPage(writer http.ResponseWriter, request *http.Request, component templ.Component, status int) {
	writer.Header().Add("Vary", "Accept")
	writer.Header().Add("Vary", "Datastar-Request")
	if isDatastarRequest(request) {
		writer.Header().Add("Vary", "Accept-Encoding")
		sse := datastar.NewSSE(writer, request, datastar.WithCompression())
		if err := sse.PatchElementTempl(component); err != nil {
			return
		}
		return
	}

	var output bytes.Buffer
	if err := component.Render(request.Context(), &output); err != nil {
		http.Error(writer, "failed to render page", http.StatusInternalServerError)
		return
	}
	writer.Header().Set("Content-Type", "text/html; charset=utf-8")
	writer.WriteHeader(status)
	_, _ = writer.Write(output.Bytes())
}
