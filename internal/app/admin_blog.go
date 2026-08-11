package app

import (
	"encoding/base64"
	"net/http"

	"sacha.house/internal/blog"
	"sacha.house/internal/web"
)

const maxBlogImageBytes = 10 << 20

func (app *App) adminBlogPosts(writer http.ResponseWriter, request *http.Request) {
	posts, err := app.blog.List(true)
	if err != nil {
		http.Error(writer, "failed to load blogposts", http.StatusInternalServerError)
		return
	}
	views := make([]web.AdminBlogPostView, len(posts))
	for index, post := range posts {
		views[index] = web.AdminBlogPostView{
			Slug: post.Slug, Title: post.Title, Status: post.Status,
			UpdatedAt: post.UpdatedAt, PublishedAt: post.PublishedAt,
		}
	}
	data := web.AdminBlogPostsPageData{
		PageData: app.page(request.URL.Path, "blogposts / admin / sacha.house", "Manage blogposts."),
		Posts:    views,
	}
	renderHTML(writer, request, web.AdminBlogPostsPage(data), http.StatusOK)
}

func (app *App) adminNewBlogPost(writer http.ResponseWriter, request *http.Request) {
	form := web.BlogPostForm{IsNew: true, FormAction: "/admin/blogposts/new", Language: "en", Status: "draft"}
	app.renderBlogEditor(writer, request, form, "", http.StatusOK)
}

func (app *App) adminCreateBlogPost(writer http.ResponseWriter, request *http.Request) {
	app.saveBlogPost(writer, request, "")
}

func (app *App) adminEditBlogPost(writer http.ResponseWriter, request *http.Request) {
	document, err := app.blog.Load(request.PathValue("slug"), true)
	if err != nil {
		http.NotFound(writer, request)
		return
	}
	form, err := blogPostForm(document)
	if err != nil {
		http.Error(writer, "failed to load blogpost", http.StatusInternalServerError)
		return
	}
	app.renderBlogEditor(writer, request, form, "", http.StatusOK)
}

func (app *App) adminSaveBlogPost(writer http.ResponseWriter, request *http.Request) {
	app.saveBlogPost(writer, request, request.PathValue("slug"))
}

func (app *App) saveBlogPost(writer http.ResponseWriter, request *http.Request, oldSlug string) {
	request.Body = http.MaxBytesReader(writer, request.Body, maxAdminFormBody)
	if err := request.ParseForm(); err != nil {
		app.renderBlogEditor(writer, request, blogPostFormFromRequest(request, oldSlug == ""), "Form data exceeds the allowed size.", http.StatusUnprocessableEntity)
		return
	}
	form := blogPostFormFromRequest(request, oldSlug == "")
	if len(form.Title) > 200 || len(form.Slug) > 200 || len(form.Markdown) > 1<<20 {
		app.renderBlogEditor(writer, request, form, "The blogpost fields exceed the allowed size.", http.StatusUnprocessableEntity)
		return
	}
	slug, err := app.blog.Save(blog.SaveInput{
		Title: form.Title, Slug: form.Slug, Language: form.Language, Status: form.Status,
		PublishedAt: form.PublishedAt, Markdown: form.Markdown,
	}, oldSlug)
	if err != nil {
		app.renderBlogEditor(writer, request, form, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	http.Redirect(writer, request, "/admin/blogposts/"+slug, http.StatusSeeOther)
}

func blogPostFormFromRequest(request *http.Request, isNew bool) web.BlogPostForm {
	action := "/admin/blogposts/new"
	if !isNew {
		action = "/admin/blogposts/" + request.PathValue("slug") + "/save"
	}
	return web.BlogPostForm{
		IsNew: isNew, FormAction: action,
		Title: request.PostForm.Get("title"), Slug: request.PostForm.Get("slug"),
		Language: request.PostForm.Get("language"), Status: request.PostForm.Get("status"), PublishedAt: request.PostForm.Get("publishedAt"),
		Markdown: request.PostForm.Get("markdown"),
	}
}

func blogPostForm(document blog.Document) (web.BlogPostForm, error) {
	publishedAt, err := blog.FormatLocalDateTime(document.Metadata.PublishedAt)
	if err != nil {
		return web.BlogPostForm{}, err
	}
	return web.BlogPostForm{
		FormAction: "/admin/blogposts/" + document.Metadata.Slug + "/save",
		Title:      document.Metadata.Title, Slug: document.Metadata.Slug, Language: document.Metadata.Language, Status: document.Metadata.Status,
		PublishedAt: publishedAt, Markdown: document.Markdown,
		PublicURL: "/blog/" + document.Metadata.Slug,
		CreatedAt: document.Metadata.CreatedAt, UpdatedAt: document.Metadata.UpdatedAt,
	}, nil
}

func (app *App) renderBlogEditor(writer http.ResponseWriter, request *http.Request, form web.BlogPostForm, message string, status int) {
	preview, err := blog.RenderMarkdown(form.Markdown)
	if err != nil {
		preview = ""
		if message == "" {
			message = "Failed to render the Markdown preview."
		}
	}
	title := "edit blogpost / admin / sacha.house"
	if form.IsNew {
		title = "new blogpost / admin / sacha.house"
	}
	data := web.AdminBlogPostEditorPageData{
		PageData: app.page(request.URL.Path, title, "Edit a blogpost."),
		Form:     form, Error: message, PreviewHTML: preview,
	}
	renderHTML(writer, request, web.AdminBlogPostEditorPage(data), status)
}

func (app *App) adminUploadBlogImage(writer http.ResponseWriter, request *http.Request) {
	maxBody := int64(base64.StdEncoding.EncodedLen(maxBlogImageBytes) + 4096)
	request.Body = http.MaxBytesReader(writer, request.Body, maxBody)
	var input struct {
		Slug       string `json:"slug"`
		Filename   string `json:"filename"`
		MIMEType   string `json:"mimeType"`
		DataBase64 string `json:"dataBase64"`
	}
	if err := decodeJSON(request, &input); err != nil {
		http.Error(writer, "invalid image payload", http.StatusUnprocessableEntity)
		return
	}
	if !supportedImageMIME(input.MIMEType) {
		http.Error(writer, "image exceeds 10 MiB or has an invalid type", http.StatusUnprocessableEntity)
		return
	}
	data, err := base64.StdEncoding.Strict().DecodeString(input.DataBase64)
	if err != nil || len(data) > maxBlogImageBytes {
		http.Error(writer, "invalid image data", http.StatusUnprocessableEntity)
		return
	}
	detectedMIME := http.DetectContentType(data)
	if !supportedImageMIME(detectedMIME) || detectedMIME != input.MIMEType {
		http.Error(writer, "image content does not match its declared type", http.StatusUnprocessableEntity)
		return
	}
	result, err := app.blog.Upload(input.Slug, input.Filename, detectedMIME, data)
	if err != nil {
		http.Error(writer, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	writeJSON(writer, http.StatusOK, result)
}

func supportedImageMIME(value string) bool {
	switch value {
	case "image/png", "image/jpeg", "image/webp", "image/gif":
		return true
	default:
		return false
	}
}
