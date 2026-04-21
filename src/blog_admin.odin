package main

import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

import http "lib:odin-http"
import temple "lib:temple"


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

require_admin :: proc(req: ^http.Request, res: ^http.Response) -> bool {
	if get_auth_level(req, res) == .Authorized {
		return true
	}
	http.headers_set(&res.headers, "Location", "/admin/login")
	http.respond(res, http.Status.Temporary_Redirect)
	return false
}

render_admin_blog_editor :: proc(req: ^http.Request, res: ^http.Response, form: Blog_Post_Form_Data, error_msg: string) {
	data := Admin_Blog_Editor_Page_Data{
		base        = create_base_page_data(
			Maybe_SEO_Data{title = "manage blogposts / sacha.house", description = "Blogpost editor."},
			req.url.path,
			true,
		),
		Error       = error_msg,
		Form        = form,
		PreviewHtml = markdown_to_html(form.Markdown, context.temp_allocator),
	}

	page_template := temple.compiled("templates/admin_blogpost_editor.temple.twig", Admin_Blog_Editor_Page_Data)
	render_page(req, res, page_template, data)
}

admin_blogposts_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	if !require_admin(req, res) {
		return
	}

	metas, err := list_blog_post_metadata(true)
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
			Maybe_SEO_Data{title = "manage blogposts / sacha.house", description = "Manage blogposts."},
			req.url.path,
			true,
		),
		Posts = posts,
	}

	page_template := temple.compiled("templates/admin_blogposts.temple.twig", Admin_Blog_List_Page_Data)
	render_page(req, res, page_template, data)
}

admin_blogpost_new_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	if !require_admin(req, res) {
		return
	}
	render_admin_blog_editor(req, res, build_blog_editor_form(empty_blog_post_document(), "", true), "")
}

admin_blogpost_edit_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	if !require_admin(req, res) {
		return
	}

	slug := req.url_params[0]
	doc, err := load_blog_post_document(slug, true)
	if err.type != .None {
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}

	render_admin_blog_editor(req, res, build_blog_editor_form(doc, slug, false), "")
}

blog_form_from_map :: proc(form_data: map[string]string) -> Blog_Post_Save_Input {
	return Blog_Post_Save_Input{
		title       = form_data["title"] or_else "",
		slug        = form_data["slug"] or_else "",
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
		PublishedAt = input.publishedAt,
		Markdown    = input.markdown,
		CreatedAt   = "",
		UpdatedAt   = "",
		IsNew       = is_new,
		FormAction  = "/admin/blogposts/new" if is_new else fmt.tprintf("/admin/blogposts/%s/save", current_slug),
		PublicUrl   = fmt.tprintf("/blog/%s", blog_slugify(input.slug)) if input.slug != "" else "",
	}
}

handle_blogpost_submit :: proc(req: ^http.Request, res: ^http.Response, old_slug: string, is_new: bool) {
	if !require_admin(req, res) {
		return
	}

	Context_Data :: struct {
		req:      ^http.Request,
		res:      ^http.Response,
		old_slug: string,
		is_new:   bool,
	}

	ctx := new_clone(Context_Data{req = req, res = res, old_slug = old_slug, is_new = is_new})
	http.body(
		req,
		-1,
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

			input := blog_form_from_map(form_data)
			saved_slug, save_err := save_blog_post(input, ctx.old_slug)
			if save_err.type != .None {
				render_admin_blog_editor(
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

admin_blogpost_create :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	handle_blogpost_submit(req, res, "", true)
}

admin_blogpost_save :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	handle_blogpost_submit(req, res, req.url_params[0], false)
}

admin_blogpost_upload_image :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	if !require_admin(req, res) {
		return
	}

	Context_Data :: struct {
		res: ^http.Response,
	}

	ctx := new_clone(Context_Data{res = res})
	http.body(
		req,
		-1,
		ctx,
		proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
			ctx := cast(^Context_Data)user_data
			defer free(ctx)
			if err != nil {
				http.respond(ctx.res, http.body_error_status(err))
				return
			}

			upload: Blog_Image_Upload_Request
			if uerr := json.unmarshal(transmute([]u8)body, &upload, allocator = context.temp_allocator); uerr != nil {
				http.respond_plain(ctx.res, "Invalid JSON payload", http.Status.Bad_Request)
				return
			}

			slug := blog_slugify(strings.trim_space(upload.slug))
			if slug == "" {
				http.respond_plain(ctx.res, "Slug is required before uploading images", http.Status.Bad_Request)
				return
			}

			ensure_err := ensure_blog_root_exists()
			if ensure_err.type != .None {
				http.respond_plain(ctx.res, ensure_err.msg, http.Status.Internal_Server_Error)
				return
			}

			assets_dir := blog_post_assets_dir(slug)
			if mkdir_err := os.make_directory_all(assets_dir); mkdir_err != nil {
				http.respond_plain(
					ctx.res,
					fmt.tprintf("Could not create assets directory: %v", mkdir_err),
					http.Status.Internal_Server_Error,
				)
				return
			}

			ext := os.ext(upload.filename)
			if ext == "" {
				ext = blog_mime_extension(upload.mimeType)
			}
			if ext == "" {
				http.respond_plain(ctx.res, "Unsupported image type", http.Status.Bad_Request)
				return
			}

			file_bytes := base64.decode(upload.dataBase64, allocator = context.temp_allocator)
			if file_bytes == nil {
				http.respond_plain(ctx.res, "Invalid base64 image payload", http.Status.Bad_Request)
				return
			}

			filename := fmt.tprintf(
				"%s-%s%s",
				blog_uploaded_file_stem(upload.filename),
				generate_random_string(8, "abcdefghijklmnopqrstuvwxyz0123456789", context.temp_allocator),
				ext,
			)
			file_path, _ := os.join_path({assets_dir, filename}, context.temp_allocator)
			if write_err := os.write_entire_file_from_bytes(file_path, file_bytes); write_err != nil {
				http.respond_plain(
					ctx.res,
					fmt.tprintf("Could not write image: %v", write_err),
					http.Status.Internal_Server_Error,
				)
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

blog_media_file :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	set_cache_header(res, "public, max-age=3600")
	http.respond_dir(res, "/media", "data", req.url.path)
}
