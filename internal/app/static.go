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

func (app *App) staticHandler() http.Handler {
	server := http.StripPrefix("/static/", http.FileServerFS(app.static))
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if app.options.Development {
			writer.Header().Set("Cache-Control", "no-store")
		} else {
			writer.Header().Set("Cache-Control", publicCache)
		}
		server.ServeHTTP(writer, request)
	})
}

func (app *App) rootStaticHandler() http.Handler {
	server := http.FileServerFS(app.static)
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if _, allowed := rootStaticAssets[request.URL.Path]; !allowed {
			http.NotFound(writer, request)
			return
		}
		writer.Header().Set("Cache-Control", publicCache)
		server.ServeHTTP(writer, request)
	})
}
