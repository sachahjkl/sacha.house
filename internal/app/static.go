package app

import "net/http"

var rootStaticAssets = map[string]struct{}{
	"/apple-touch-icon.png": {},
	"/browserconfig.xml":    {},
	"/favicon-16x16.png":    {},
	"/favicon-32x32.png":    {},
	"/favicon.ico":          {},
	"/favicon.png":          {},
	"/favicon_shadow.png":   {},
	"/robots.txt":           {},
	"/sachahjkl.gpg":        {},
	"/sachahjkl.pub":        {},
}

// textRootAssets are plain-text key files. Their extensions map to unrelated
// binary types (.pub is Microsoft Publisher), which makes browsers download
// them instead of showing the key.
var textRootAssets = map[string]struct{}{
	"/sachahjkl.gpg": {},
	"/sachahjkl.pub": {},
}

func (app *App) staticHandler() http.Handler {
	server := http.StripPrefix("/static/", http.FileServerFS(app.static))
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		switch {
		case app.options.Development:
			writer.Header().Set("Cache-Control", "no-store")
		case request.URL.Query().Get("v") != "":
			// The pages add ?v=<commit> to the stylesheet and the scripts: a new build is a new URL.
			writer.Header().Set("Cache-Control", immutableCache)
		default:
			writer.Header().Set("Cache-Control", publicCache)
		}
		server.ServeHTTP(writer, request)
	})
}

func (app *App) rootStaticHandler() http.Handler {
	server := http.FileServerFS(app.static)
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if _, allowed := rootStaticAssets[request.URL.Path]; !allowed {
			app.notFound(writer, request)
			return
		}
		writer.Header().Set("Cache-Control", publicCache)
		if _, text := textRootAssets[request.URL.Path]; text {
			writer.Header().Set("Content-Type", "text/plain; charset=utf-8")
			writer.Header().Set("Content-Disposition", "inline")
		}
		server.ServeHTTP(writer, request)
	})
}
