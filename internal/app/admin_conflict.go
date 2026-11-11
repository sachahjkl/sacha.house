package app

import (
	"bytes"
	"errors"
	"io/fs"
	"net/http"
	"strconv"

	"sacha.house/internal/blog"
	"sacha.house/internal/web"
)

// blogConflictCount counts the posts that wait for a conflict resolution.
func (app *App) blogConflictCount() int {
	posts, err := app.blog.List(true)
	if err != nil {
		return 0
	}
	count := 0
	for _, post := range posts {
		if app.blog.HasConflict(post.Slug) {
			count++
		}
	}
	return count
}

func (app *App) adminBlogConflict(writer http.ResponseWriter, request *http.Request) {
	app.renderBlogConflict(writer, request, "", http.StatusOK)
}

func (app *App) renderBlogConflict(writer http.ResponseWriter, request *http.Request, message string, status int) {
	slug := request.PathValue("slug")
	conflict, err := app.blog.Conflict(slug)
	if errors.Is(err, blog.ErrNoConflict) {
		http.Redirect(writer, request, "/admin/blogposts/"+slug, http.StatusSeeOther)
		return
	}
	if err != nil {
		http.NotFound(writer, request)
		return
	}
	site, repository := conflict.Site.Metadata, conflict.Repository.Metadata
	data := web.AdminBlogConflictPageData{
		PageData: app.page(request.URL.Path, "conflict / admin / sacha.house", "Resolve a blogpost conflict."),
		Slug:     slug, Title: site.Title, Error: message,
		Fields: []web.ConflictField{
			{Name: "title", Site: site.Title, Repository: repository.Title},
			{Name: "description", Site: site.Description, Repository: repository.Description},
			{Name: "slug", Site: site.Slug, Repository: repository.Slug},
			{Name: "language", Site: site.Language, Repository: repository.Language},
			{Name: "status", Site: site.Status, Repository: repository.Status},
			{Name: "published at", Site: site.PublishedAt, Repository: repository.PublishedAt},
			{Name: "updated at", Site: site.UpdatedAt, Repository: repository.UpdatedAt},
		},
		Content: web.LineDiff(conflict.Site.Markdown, conflict.Repository.Markdown),
	}
	renderHTML(writer, request, web.AdminBlogConflictPage(data), status)
}

func (app *App) adminTakeRepositoryVersion(writer http.ResponseWriter, request *http.Request) {
	app.resolveBlogConflict(writer, request, app.blog.TakeRepositoryVersion)
}

func (app *App) adminKeepSiteVersion(writer http.ResponseWriter, request *http.Request) {
	app.resolveBlogConflict(writer, request, app.blog.KeepSiteVersion)
}

func (app *App) resolveBlogConflict(writer http.ResponseWriter, request *http.Request, resolve func(slug string) error) {
	slug := request.PathValue("slug")
	if err := resolve(slug); err != nil {
		if errors.Is(err, blog.ErrNoConflict) {
			http.Redirect(writer, request, "/admin/blogposts", http.StatusSeeOther)
			return
		}
		app.renderBlogConflict(writer, request, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	http.Redirect(writer, request, "/admin/blogposts", http.StatusSeeOther)
}

// adminDownloadBlogPost sends the site version of a post as a zip, to copy into data/blog of the repository.
func (app *App) adminDownloadBlogPost(writer http.ResponseWriter, request *http.Request) {
	slug := request.PathValue("slug")
	var archive bytes.Buffer
	if err := app.blog.WriteArchive(slug, &archive); err != nil {
		if errors.Is(err, fs.ErrNotExist) || errors.Is(err, blog.ErrInvalidSlug) {
			http.NotFound(writer, request)
			return
		}
		http.Error(writer, "failed to archive the blogpost", http.StatusInternalServerError)
		return
	}
	writer.Header().Set("Content-Type", "application/zip")
	writer.Header().Set("Content-Disposition", `attachment; filename="`+slug+`.zip"`)
	writer.Header().Set("Content-Length", strconv.Itoa(archive.Len()))
	_, _ = writer.Write(archive.Bytes())
}
