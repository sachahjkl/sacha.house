package main

import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:strings"

import http "lib:odin-http"
import temple "lib:temple"

MAX_BLOGPOST_FORM_BODY_BYTES  :: 2 * 1024 * 1024
MAX_BLOG_IMAGE_UPLOAD_BODY_BYTES :: 16 * 1024 * 1024


Admin_Blog_List_Page_Data :: struct {
	using base: Base_Page_Data,
	Posts:      []Admin_Blog_List_Item,
}

Admin_Blog_Editor_Page_Data :: struct {
	using base:  Base_Page_Data,
	Error:       string,
	Form:        Blog_Post_Form_Data,
	PreviewHtml: string,
}

Blog_Image_Upload_Request :: struct {
	slug:       string,
	filename:   string,
	mimeType:   string,
	dataBase64: string,
}

Blog_Image_Upload_Response :: struct {
	url:      string,
	markdown: string,
}

Ensure_Admin_Next :: enum {
	RedirectLogin,
	Unauthorized,
}

ensure_admin :: proc(
	app: ^App_State,
	req: ^http.Request,
	res: ^http.Response,
	do_next: Ensure_Admin_Next = .Unauthorized,
) -> bool {
	if get_auth_level(&app.sessions, &app.config, req, res) == .Authorized {
		return true
	}

	switch do_next {
	case .RedirectLogin:
		http.headers_set(&res.headers, "Location", "/admin/login")
		http.respond(res, http.Status.Temporary_Redirect)
	case .Unauthorized:
		http.respond_with_status(res, http.Status.Unauthorized)
	}

	return false
}

render_admin_blog_editor :: proc(app: ^App_State, req: ^http.Request, res: ^http.Response, form: Blog_Post_Form_Data, error_msg: string) {
	http.headers_set(&res.headers, "Cache-Control", "no-store")
	csrf_storage: [SESSION_CSRF_TOKEN_BYTES]byte
	csrf_token, csrf_ok := session_csrf_token(&app.sessions, req, csrf_storage[:])
	if !csrf_ok {
		http.respond_with_status(res, http.Status.Unauthorized)
		return
	}
	defer wipe_session_csrf_token(csrf_token)
	data := Admin_Blog_Editor_Page_Data{
		base        = create_base_page_data(
			app,
			Maybe_SEO_Data{title = "manage blogposts / sacha.house", description = "Blogpost editor."},
			req.url.path,
			true,
		),
		Error       = error_msg,
		Form        = form,
		PreviewHtml = markdown_to_html(form.Markdown, context.temp_allocator),
	}
	data.Form.CsrfToken = csrf_token

	page_template := temple.compiled("templates/admin_blogpost_editor.temple.twig", Admin_Blog_Editor_Page_Data)
	render_page(req, res, page_template, data)
}

admin_blogposts_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin(app, req, res, .RedirectLogin) {
		return
	}

	metas, err := list_blog_post_metadata(&app.blog, true)
	if err.type != .None {
		http.respond_plain(res, err.msg, http.Status.Internal_Server_Error)
		return
	}

	posts := make([]Admin_Blog_List_Item, len(metas), context.temp_allocator)
	for meta, i in metas {
		posts[i] = Admin_Blog_List_Item{
			Title       = meta.title,
			Slug        = meta.slug,
			Status      = meta.status,
			UpdatedAt   = meta.updatedAt,
			PublishedAt = meta.publishedAt,
		}
	}

	data := Admin_Blog_List_Page_Data{
		base  = create_base_page_data(
			app,
			Maybe_SEO_Data{title = "manage blogposts / sacha.house", description = "Manage blogposts."},
			req.url.path,
			true,
		),
		Posts = posts,
	}

	page_template := temple.compiled("templates/admin_blogposts.temple.twig", Admin_Blog_List_Page_Data)
	render_page(req, res, page_template, data)
}

admin_blogpost_new_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin(app, req, res, .RedirectLogin) {
		return
	}
	render_admin_blog_editor(
		app,
		req,
		res,
		build_blog_editor_form(empty_blog_post_document(&app.blog), "", true, app.timezone),
		"",
	)
}

admin_blogpost_edit_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin(app, req, res, .RedirectLogin) {
		return
	}

	slug := req.url_params[0]
	doc, err := load_blog_post_document(&app.blog, slug, true)
	if err.type != .None {
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}

	render_admin_blog_editor(app, req, res, build_blog_editor_form(doc, slug, false, app.timezone), "")
}

blog_form_from_map :: proc(form_data: map[string]string) -> Blog_Post_Save_Input {
	return Blog_Post_Save_Input{
		title       = form_data["title"] or_else "",
		slug        = form_data["slug"] or_else "",
		language    = form_data["language"] or_else "en",
		status      = form_data["status"] or_else "draft",
		publishedAt = form_data["publishedAt"] or_else "",
		markdown    = form_data["markdown"] or_else "",
	}
}

blog_form_to_editor_form :: proc(input: Blog_Post_Save_Input, current_slug: string, is_new: bool) -> Blog_Post_Form_Data {
	return Blog_Post_Form_Data{
		Title       = input.title,
		Slug        = input.slug,
		Status      = blog_status_normalize(input.status),
		Language     = input.language,
		PublishedAt = input.publishedAt,
		Markdown    = input.markdown,
		CreatedAt   = "",
		UpdatedAt   = "",
		IsNew       = is_new,
		FormAction  = "/admin/blogposts/new" if is_new else fmt.tprintf("/admin/blogposts/%s/save", current_slug),
		PublicUrl   = fmt.tprintf("/blog/%s", blog_slugify(input.slug)) if input.slug != "" else "",
	}
}

handle_blogpost_submit :: proc(app: ^App_State, req: ^http.Request, res: ^http.Response, old_slug: string, is_new: bool) {
	if !ensure_admin_post(app, req, res) {
		return
	}

	Context_Data :: struct {
		app:      ^App_State,
		req:      ^http.Request,
		res:      ^http.Response,
		old_slug: string,
		is_new:   bool,
	}

	ctx := new_clone(Context_Data{app = app, req = req, res = res, old_slug = old_slug, is_new = is_new})
	http.body(
		req,
		MAX_BLOGPOST_FORM_BODY_BYTES,
		ctx,
		proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
			ctx := cast(^Context_Data)user_data
			defer free(ctx)
			if err != nil {
				http.respond(ctx.res, http.body_error_status(err))
				return
			}

			form_data, ok := http.body_url_encoded(body)
			if !ok {
				http.respond_with_status(ctx.res, http.Status.Bad_Request)
				return
			}
			if !validate_admin_post_csrf(
				ctx.app,
				ctx.req,
				ctx.res,
				form_data["csrf_token"] or_else "",
			) {
				return
			}

			input := blog_form_from_map(form_data)
			saved_slug, save_err := save_blog_post(&ctx.app.blog, input, ctx.app.timezone, ctx.old_slug)
			if save_err.type != .None {
				render_admin_blog_editor(
					ctx.app,
					ctx.req,
					ctx.res,
					blog_form_to_editor_form(input, ctx.old_slug, ctx.is_new),
					save_err.msg,
				)
				return
			}

			http.headers_set(&ctx.res.headers, "Location", fmt.tprintf("/admin/blogposts/%s", saved_slug))
			http.respond(ctx.res, http.Status.See_Other)
		},
	)
}

admin_blogpost_create :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	handle_blogpost_submit(app, req, res, "", true)
}

admin_blogpost_save :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	handle_blogpost_submit(app, req, res, req.url_params[0], false)
}

admin_blogpost_upload_image :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin_post(app, req, res) || !validate_admin_post_csrf_header(app, req, res) {
		return
	}

	Context_Data :: struct {
		app: ^App_State,
		res: ^http.Response,
	}

	ctx := new_clone(Context_Data{app = app, res = res})
	http.body(
		req,
		MAX_BLOG_IMAGE_UPLOAD_BODY_BYTES,
		ctx,
		proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
			ctx := cast(^Context_Data)user_data
			defer free(ctx)
			if err != nil {
				http.respond(ctx.res, http.body_error_status(err))
				return
			}

			upload: Blog_Image_Upload_Request
			if unmarshal_err := json.unmarshal(transmute([]u8)body, &upload, allocator = context.temp_allocator); unmarshal_err != nil {
				http.respond_plain(ctx.res, "Invalid JSON payload", http.Status.Bad_Request)
				return
			}

			raw_slug := strings.trim_space(upload.slug)
			if raw_slug == "" {
				http.respond_plain(ctx.res, "Slug is required before uploading images", http.Status.Bad_Request)
				return
			}
			slug := blog_slugify(raw_slug)
			if !blog_slug_is_valid(slug) {
				http.respond_plain(ctx.res, "Invalid blogpost slug", http.Status.Bad_Request)
				return
			}

			mime_type := strings.trim_space(upload.mimeType)
			ext := blog_mime_extension(mime_type)
			if ext == "" || !blog_upload_extension_matches(upload.filename, mime_type) {
				http.respond_plain(ctx.res, "Unsupported or mismatched image type", http.Status.Bad_Request)
				return
			}
			file_bytes := base64.decode(upload.dataBase64, allocator = context.temp_allocator)
			if file_bytes == nil || !blog_asset_bytes_match_extension(ext, file_bytes) {
				http.respond_plain(ctx.res, "Invalid image payload", http.Status.Bad_Request)
				return
			}

			filename := fmt.tprintf(
				"%s-%s%s",
				blog_uploaded_file_stem(upload.filename),
				generate_random_string(8, "abcdefghijklmnopqrstuvwxyz0123456789", context.temp_allocator),
				ext,
			)
			if save_err := save_blog_asset(&ctx.app.blog, slug, filename, file_bytes); save_err.type != .None {
				status := http.Status.Bad_Request if save_err.type == .Validation else http.Status.Internal_Server_Error
				http.respond_plain(ctx.res, save_err.msg, status)
				return
			}

			url := blog_uploaded_asset_url(slug, filename)
			response := Blog_Image_Upload_Response{
				url      = url,
				markdown = fmt.tprintf("![%s](%s)", blog_uploaded_file_stem(upload.filename), url),
			}
			http.respond_json(ctx.res, response, http.Status.OK)
		},
	)
}

blog_media_file :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if len(req.url_params) != 2 {
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}
	slug, filename := req.url_params[0], req.url_params[1]
	asset_bytes, load_err := load_published_blog_asset(&app.blog, slug, filename)
	if load_err.type != .None {
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}
	set_cache_header(res, "no-store")
	http.respond_file_content(res, filename, asset_bytes, http.Status.OK)
}
