package app

import (
	"errors"
	"mime"
	"net/http"
	"path"
	"strings"
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
	query := strings.TrimSpace(request.URL.Query().Get("q"))
	if len(query) > maxSearchLength {
		query = query[:maxSearchLength]
	}
	groups := make([]web.PostYearGroup, 0)
	for _, metadata := range posts {
		document, err := app.blog.Load(metadata.Slug, false)
		if err != nil {
			continue
		}
		if query != "" && !blog.Matches(document, query) {
			continue
		}
		view := metadataView(document.Metadata)
		view.Excerpt = postDescription(document)
		if query != "" {
			view.Excerpt = blog.SearchSnippet(document, query, view.Excerpt)
		}
		year := web.LocalYear(parseTime(metadata.PublishedAt))
		if len(groups) == 0 || groups[len(groups)-1].Year != year {
			groups = append(groups, web.PostYearGroup{Year: year})
		}
		groups[len(groups)-1].Posts = append(groups[len(groups)-1].Posts, view)
	}
	data := web.BlogPageData{
		PageData:   app.page(request.URL.Path, "blog / sacha.house", web.Me.FullName+"'s blog: software, systems, the tools I build, and the occasional recipe."),
		YearGroups: groups, Query: query,
	}
	if query == "" {
		data.PageData.SEO.StructuredData = web.BlogStructuredData()
	} else {
		// A search result page is not a page of its own for search engines.
		data.PageData.Title = "search: " + query + " / blog / sacha.house"
		data.PageData.SEO.NoIndex = true
	}
	renderHTML(writer, request, web.BlogPage(data), http.StatusOK)
}

// maxSearchLength bounds the query of /blog?q=, in bytes.
const maxSearchLength = 200

// morePosts is how many other posts a post links to at its end.
const morePosts = 3

func (app *App) blogPost(writer http.ResponseWriter, request *http.Request) {
	document, err := app.blog.Load(request.PathValue("slug"), false)
	if err != nil {
		app.notFound(writer, request)
		return
	}
	metadata := document.Metadata
	view := metadataView(metadata)
	assets := app.blog.Assets(metadata.Slug)
	html, err := blog.RenderPost(document.Markdown, assets)
	if err != nil {
		http.Error(writer, "failed to render blog post", http.StatusInternalServerError)
		return
	}
	view.HTML = html
	for _, entry := range blog.TableOfContents(document.Markdown) {
		view.TOC = append(view.TOC, web.TOCItem{Level: entry.Level, ID: entry.ID, Title: entry.Title})
	}
	page := app.page(request.URL.Path, metadata.Title+" / sacha.house", postDescription(document))
	page.Language = metadata.Language
	page.SEO.Type = "article"
	page.SEO.PublishedTime = metadata.PublishedAt
	page.SEO.ModifiedTime = metadata.UpdatedAt
	if page.SEO.ModifiedTime == "" {
		page.SEO.ModifiedTime = metadata.PublishedAt
	}
	if cover, found := assets.Cover(document.Markdown); found {
		page.SEO.Image, page.SEO.ImageWidth, page.SEO.ImageHeight = web.SiteURL+cover.URL, cover.Width, cover.Height
		page.SEO.ImageAlt = cover.Alt
		if page.SEO.ImageAlt == "" {
			page.SEO.ImageAlt = metadata.Title
		}
	}
	page.SEO.StructuredData = web.PostStructuredData(page.SEO, metadata.Title, metadata.Language)
	data := web.PostPageData{PageData: page, Post: view, More: app.otherPosts(metadata.Slug, morePosts)}
	renderHTML(writer, request, web.PostPage(data), http.StatusOK)
}

// postDescription is the summary of a post: its own description, or an excerpt of its text.
func postDescription(document blog.Document) string {
	if document.Metadata.Description != "" {
		return document.Metadata.Description
	}
	return blog.Excerpt(document.Markdown, blog.ExcerptLength)
}

// otherPosts returns the newest published posts other than slug.
func (app *App) otherPosts(slug string, limit int) []web.PostView {
	posts, err := app.blog.List(false)
	if err != nil {
		return nil
	}
	views := make([]web.PostView, 0, limit)
	for _, metadata := range posts {
		if len(views) == limit {
			break
		}
		if metadata.Slug != slug {
			views = append(views, metadataView(metadata))
		}
	}
	return views
}

func metadataView(metadata blog.Metadata) web.PostView {
	created := parseTime(metadata.CreatedAt)
	updated := parseTime(metadata.UpdatedAt)
	if updated.IsZero() {
		updated = created
	}
	return web.PostView{
		Slug: metadata.Slug, Title: metadata.Title, Description: metadata.Description, Language: metadata.Language,
		PublishedOn: web.FormatDate(parseTime(metadata.PublishedAt)),
		CreatedOn:   web.FormatDate(created), CreatedAtTime: web.FormatTime(created),
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
	session, signedIn := app.auth.SessionFromRequest(request)
	admin := signedIn && session.UserID == adminUserID
	file, err := app.blog.OpenPublishedAsset(slug, assetPath)
	draft := admin && errors.Is(err, blog.ErrNotPublished)
	if draft {
		file, err = app.blog.OpenAsset(slug, assetPath)
	}
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
	if draft {
		writer.Header().Set("Cache-Control", "no-store")
	} else {
		writer.Header().Set("Cache-Control", publicCache)
	}
	if contentType := mime.TypeByExtension(path.Ext(assetPath)); contentType != "" {
		writer.Header().Set("Content-Type", contentType)
	}
	http.ServeContent(writer, request, info.Name(), info.ModTime(), file)
}
