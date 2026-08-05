package app

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"

	"github.com/a-h/templ"
)

func (app *App) requestIP(request *http.Request) string {
	direct := request.RemoteAddr
	if host, _, err := net.SplitHostPort(direct); err == nil {
		direct = host
	}
	directIP := net.ParseIP(direct)
	if app.config.TrustProxyHTTPS && directIP != nil && directIP.IsLoopback() {
		if address := parseForwardedIP(request.Header.Get("X-Real-IP")); address != "" {
			return address
		}
		forwarded := strings.Split(request.Header.Get("X-Forwarded-For"), ",")
		for index := len(forwarded) - 1; index >= 0; index-- {
			if address := parseForwardedIP(forwarded[index]); address != "" {
				return address
			}
		}
	}
	return direct
}

func parseForwardedIP(value string) string {
	address := net.ParseIP(strings.TrimSpace(value))
	if address == nil {
		return ""
	}
	return address.String()
}

func decodeJSON(request *http.Request, output any) error {
	decoder := json.NewDecoder(request.Body)
	if err := decoder.Decode(output); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("request contains trailing JSON")
	}
	return nil
}

func writeJSON(writer http.ResponseWriter, status int, value any) {
	writer.Header().Set("Content-Type", "application/json; charset=utf-8")
	writer.Header().Set("Cache-Control", "no-store")
	writer.WriteHeader(status)
	_ = json.NewEncoder(writer).Encode(value)
}

func renderHTML(writer http.ResponseWriter, request *http.Request, component templ.Component, status int) {
	var output bytes.Buffer
	if err := component.Render(request.Context(), &output); err != nil {
		http.Error(writer, fmt.Sprintf("failed to render HTML: %v", err), http.StatusInternalServerError)
		return
	}
	writer.Header().Set("Content-Type", "text/html; charset=utf-8")
	writer.WriteHeader(status)
	_, _ = writer.Write(output.Bytes())
}
