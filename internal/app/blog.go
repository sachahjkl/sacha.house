package app

import (
	"mime"
	"net/http"
	"path"
	"time"

	"sacha.house/internal/blog"
	"sacha.house/internal/web"
)

func (app *App) blogIndex(writer http.ResponseWriter, request *http.Request) {
	posts, err := app.blog.List(false)
	if err != nil {
		http.Error(writer, "failed to load blog", http.StatusInternalServerError)
		return
	}
	groups := make([]web.PostYearGroup, 0)
	for _, metadata := range posts {
		document, err := app.blog.Load(metadata.Slug, false)
		if err != nil {
			continue
		}
		view := postView(document)
		view.Excerpt = blog.Excerpt(document.Markdown, blog.ExcerptLength)
		year := web.LocalYear(parseTime(metadata.PublishedAt))
		if len(groups) == 0 || groups[len(groups)-1].Year != year {
			groups = append(groups, web.PostYearGroup{Year: year})
		}
		groups[len(groups)-1].Posts = append(groups[len(groups)-1].Posts, view)
	}
	data := web.BlogPageData{
		PageData:   app.page(request.URL.Path, "blog / sacha.house", "My blog about subjects often related to computer science."),
		YearGroups: groups,
	}
	renderHTML(writer, request, web.BlogPage(data), http.StatusOK)
}

func (app *App) blogPost(writer http.ResponseWriter, request *http.Request) {
	document, err := app.blog.Load(request.PathValue("slug"), false)
	if err != nil {
		http.NotFound(writer, request)
		return
	}
	view := postView(document)
	html, err := blog.RenderMarkdown(document.Markdown)
	if err != nil {
		http.Error(writer, "failed to render blog post", http.StatusInternalServerError)
		return
	}
	view.HTML = html
	data := web.PostPageData{
		PageData: app.page(request.URL.Path, document.Metadata.Title+" / sacha.house", blog.Excerpt(document.Markdown, blog.ExcerptLength)),
		Post:     view,
	}
	data.PageData.Language = document.Metadata.Language
	renderHTML(writer, request, web.PostPage(data), http.StatusOK)
}

func postView(document blog.Document) web.PostView {
	created := parseTime(document.Metadata.CreatedAt)
	updated := parseTime(document.Metadata.UpdatedAt)
	if updated.IsZero() {
		updated = created
	}
	return web.PostView{
		Slug: document.Metadata.Slug, Title: document.Metadata.Title,
		CreatedOn: web.FormatDate(created), CreatedAtTime: web.FormatTime(created),
		UpdatedOn: web.FormatDate(updated), UpdatedAtTime: web.FormatTime(updated),
	}
}

func parseTime(value string) time.Time {
	parsed, _ := time.Parse(time.RFC3339Nano, value)
	return parsed
}

func (app *App) blogMedia(writer http.ResponseWriter, request *http.Request) {
	slug := request.PathValue("slug")
	assetPath := request.PathValue("path")
	file, err := app.blog.OpenPublishedAsset(slug, assetPath)
	if err != nil {
		http.NotFound(writer, request)
		return
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		http.NotFound(writer, request)
		return
	}
	writer.Header().Set("Cache-Control", publicCache)
	if contentType := mime.TypeByExtension(path.Ext(assetPath)); contentType != "" {
		writer.Header().Set("Content-Type", contentType)
	}
	http.ServeContent(writer, request, info.Name(), info.ModTime(), file)
}
