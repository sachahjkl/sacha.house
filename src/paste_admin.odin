package main

import "core:fmt"
import "core:time"

import http "lib:odin-http"
import temple "lib:temple"

Admin_Paste_List_Item :: struct {
	GistId:        string,
	Revision:      string,
	KeyId:         string,
	PasteId:       string,
	Title:         string,
	CreatedAt:     string,
	UpdatedAt:     string,
	Status:        string,
	CanEdit:       bool,
	NeedsRotation: bool,
}

Admin_Paste_List_Page_Data :: struct {
	using base: Base_Page_Data,
	Items:       []Admin_Paste_List_Item,
	Error:       string,
	Notice:      string,
	CsrfToken:   string,
	Truncated:   bool,
}

Paste_Form_Data :: struct {
	GistId:        string,
	Revision:      string,
	Title:         string,
	Body:          string,
	KeyId:         string,
	CsrfToken:     string,
	FormAction:    string,
	IsNew:         bool,
	NeedsRotation: bool,
}

Admin_Paste_Editor_Page_Data :: struct {
	using base: Base_Page_Data,
	Form:        Paste_Form_Data,
	Error:       string,
	Notice:      string,
}

Paste_Admin_Mutation :: enum {
	Create,
	Save,
	Rotate,
	Delete,
}

Paste_Admin_Mutation_Context :: struct {
	app:     ^App_State,
	req:     ^http.Request,
	res:     ^http.Response,
	action:  Paste_Admin_Mutation,
	gist_id: string,
}

paste_admin_now_ms :: proc() -> i64 {
	return time.time_to_unix_nano(time.now()) / 1_000_000
}

paste_admin_gist_id_valid :: proc(id: string) -> bool {
	if len(id) < 1 || len(id) > GIST_MAX_ID_BYTES {
		return false
	}
	for c in id {
		switch c {
		case '0'..='9', 'a'..='f', 'A'..='F':
		case: return false
		}
	}
	return true
}

paste_admin_revision_valid :: proc(revision: string) -> bool {
	if len(revision) < 1 || len(revision) > PASTE_STORE_MAX_REVISION_BYTES {
		return false
	}
	for c in revision {
		switch c {
		case '0'..='9', 'a'..='f', 'A'..='F':
		case: return false
		}
	}
	return true
}


paste_admin_form_body_limit :: proc(app: ^App_State) -> int {
	return app.config.PASTE_MAX_BODY_BYTES * 3 + 8192
}

paste_admin_error_status :: proc(err: Paste_Error, client_input := false) -> http.Status {
	switch err.kind {
	case .None:                 return .OK
	case .Disabled:             return .Not_Found
	case .Invalid_Input:        return .Unprocessable_Content
	case .Not_Found, .Not_Ours: return .Not_Found
	case .Conflict:             return .Conflict
	case .Unknown_Key, .Corrupt:
		return .Unprocessable_Content
	case .Rate_Limited:         return .Too_Many_Requests
	case .Upstream_Unavailable: return .Service_Unavailable
	case .Too_Large:
		return .Payload_Too_Large if client_input else .Bad_Gateway
	case .Outcome_Unknown:      return .Bad_Gateway
	}
	return .Service_Unavailable
}

paste_admin_set_retry_after :: proc(res: ^http.Response, err: Paste_Error) {
	if err.kind == .Rate_Limited && err.retry_after_seconds > 0 {
		http.headers_set(&res.headers, "Retry-After", fmt.tprintf("%d", err.retry_after_seconds))
	}
}

paste_admin_notice :: proc(query: string) -> string {
	switch query {
	case "notice=created": return "Encrypted paste created."
	case "notice=saved":   return "Encrypted paste saved."
	case "notice=rotated": return "Encrypted paste re-encrypted with the active key."
	case "notice=deleted": return "Encrypted paste deleted."
	}
	return ""
}

paste_admin_render_editor :: proc(
	app: ^App_State,
	req: ^http.Request,
	res: ^http.Response,
	form: Paste_Form_Data,
	error_message, notice: string,
	status := http.Status.OK,
) {
	http.headers_set(&res.headers, "Cache-Control", "no-store")
	csrf_storage: [SESSION_CSRF_TOKEN_BYTES]byte
	csrf_token, csrf_ok := session_csrf_token(&app.sessions, req, csrf_storage[:])
	if !csrf_ok {
		http.respond_with_status(res, http.Status.Unauthorized)
		return
	}
	defer wipe_session_csrf_token(csrf_token)
	data := Admin_Paste_Editor_Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data {
				title = "encrypted paste editor / sacha.house",
				description = "Admin encrypted paste editor.",
			},
			req.url.path,
			true,
		),
		Form = form,
		Error = error_message,
		Notice = notice,
	}
	data.Form.CsrfToken = csrf_token
	page_template := temple.compiled(
		"templates/admin_paste_editor.temple.twig",
		Admin_Paste_Editor_Page_Data,
	)
	render_page(req, res, page_template, data, status)
}

paste_admin_form_from_loaded :: proc(loaded: ^Paste_Loaded) -> Paste_Form_Data {
	return Paste_Form_Data {
		GistId = loaded.gist_id,
		Revision = loaded.revision,
		Title = loaded.document.title,
		Body = loaded.document.body,
		KeyId = loaded.key_id,
		FormAction = fmt.tprintf("/admin/pastes/%s/save", loaded.gist_id),
		IsNew = false,
		NeedsRotation = loaded.needs_rotation,
	}
}

paste_admin_list_status :: proc(status: Paste_List_Status) -> string {
	switch status {
	case .Ready:          return "ready"
	case .Needs_Rotation: return "needs rotation"
	case .Unknown_Key:    return "key unavailable"
	case .Corrupt:        return "corrupt or unauthenticated"
	}
	return "unavailable"
}

paste_admin_list_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	if !ensure_admin(app, req, res, .RedirectLogin) {
		return
	}
	if !app.pastes.enabled {
		http.headers_set(&res.headers, "Cache-Control", "no-store")
		csrf_storage: [SESSION_CSRF_TOKEN_BYTES]byte
		csrf_token, csrf_ok := session_csrf_token(&app.sessions, req, csrf_storage[:])
		if !csrf_ok {
			http.respond_with_status(res, http.Status.Unauthorized)
			return
		}
		defer wipe_session_csrf_token(csrf_token)
		data := Admin_Paste_List_Page_Data {
			base = create_base_page_data(
				app,
				Maybe_SEO_Data {
					title = "encrypted pastes / sacha.house",
					description = "Manage encrypted GitHub Gist pastes.",
				},
				req.url.path,
				true,
			),
			Error = "Encrypted pastes are disabled. Set PASTE_ENABLED and PASTE_SECRETS_FILE.",
			CsrfToken = csrf_token,
		}
		page_template := temple.compiled(
			"templates/admin_pastes.temple.twig",
			Admin_Paste_List_Page_Data,
		)
		render_page(req, res, page_template, data, http.Status.Service_Unavailable)
		return
	}
	http.headers_set(&res.headers, "Cache-Control", "no-store")

	summaries, truncated, list_err := paste_store_list(&app.pastes.store, context.temp_allocator)
	defer paste_summaries_destroy(summaries, context.temp_allocator)
	items := make([]Admin_Paste_List_Item, len(summaries), context.temp_allocator)
	for summary, i in summaries {
		can_edit := summary.status == .Ready || summary.status == .Needs_Rotation
		items[i] = Admin_Paste_List_Item {
			GistId = summary.gist_id,
			Revision = summary.revision,
			KeyId = summary.key_id,
			PasteId = summary.paste_id,
			Title = summary.title,
			CreatedAt = summary.created_at,
			UpdatedAt = summary.updated_at,
			Status = paste_admin_list_status(summary.status),
			CanEdit = can_edit,
			NeedsRotation = summary.status == .Needs_Rotation,
		}
	}

	csrf_storage: [SESSION_CSRF_TOKEN_BYTES]byte
	csrf_token, csrf_ok := session_csrf_token(&app.sessions, req, csrf_storage[:])
	if !csrf_ok {
		http.respond_with_status(res, http.Status.Unauthorized)
		return
	}
	defer wipe_session_csrf_token(csrf_token)

	error_message := ""
	if list_err.kind != .None {
		error_message = list_err.message
		truncated = true
		paste_admin_set_retry_after(res, list_err)
	}
	data := Admin_Paste_List_Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data {
				title = "encrypted pastes / sacha.house",
				description = "Manage encrypted GitHub Gist pastes.",
			},
			req.url.path,
			true,
		),
		Items = items,
		Error = error_message,
		Notice = paste_admin_notice(req.url.query),
		CsrfToken = csrf_token,
		Truncated = truncated,
	}
	page_template := temple.compiled(
		"templates/admin_pastes.temple.twig",
		Admin_Paste_List_Page_Data,
	)
	render_page(req, res, page_template, data, http.Status.OK)
}

paste_admin_new_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	if !ensure_admin(app, req, res, .RedirectLogin) {
		return
	}
	if !app.pastes.enabled {
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}
	paste_admin_render_editor(
		app,
		req,
		res,
		Paste_Form_Data {
			FormAction = "/admin/pastes/new",
			IsNew = true,
		},
		"",
		"",
	)
}

paste_admin_edit_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	if !ensure_admin(app, req, res, .RedirectLogin) {
		return
	}
	if !app.pastes.enabled || len(req.url_params) != 1 || !paste_admin_gist_id_valid(req.url_params[0]) {
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}
	gist_id := req.url_params[0]
	loaded, load_err := paste_store_get(&app.pastes.store, gist_id, context.temp_allocator)
	defer paste_loaded_destroy(&loaded, context.temp_allocator)
	if load_err.kind == .Not_Found || load_err.kind == .Not_Ours {
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}
	if load_err.kind != .None {
		paste_admin_set_retry_after(res, load_err)
		paste_admin_render_editor(
			app,
			req,
			res,
			Paste_Form_Data {
				GistId = gist_id,
				FormAction = fmt.tprintf("/admin/pastes/%s/save", gist_id),
				IsNew = false,
			},
			load_err.message,
			"",
			paste_admin_error_status(load_err),
		)
		return
	}
	paste_admin_render_editor(
		app,
		req,
		res,
		paste_admin_form_from_loaded(&loaded),
		"",
		paste_admin_notice(req.url.query),
	)
}

paste_admin_begin_mutation :: proc(
	app: ^App_State,
	req: ^http.Request,
	res: ^http.Response,
	action: Paste_Admin_Mutation,
	gist_id := "",
) {
	if !ensure_admin(app, req, res) {
		return
	}
	if !app.pastes.enabled {
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}
	if !admin_request_same_origin(&app.config, req) {
		http.respond_with_status(res, http.Status.Forbidden)
		return
	}
	if action != .Create && !paste_admin_gist_id_valid(gist_id) {
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}
	ctx := new_clone(Paste_Admin_Mutation_Context {
		app = app,
		req = req,
		res = res,
		action = action,
		gist_id = gist_id,
	})
	http.body(req, paste_admin_form_body_limit(app), ctx, paste_admin_mutation_body)
}

paste_admin_mutation_body :: proc(user_data: rawptr, body: http.Body, body_err: http.Body_Error) {
	ctx := cast(^Paste_Admin_Mutation_Context)user_data
	defer free(ctx)
	if body_err != nil {
		http.respond(ctx.res, http.body_error_status(body_err))
		return
	}
	defer paste_wipe_string(string(body))
	form_data, form_ok := http.body_url_encoded(body)
	if !form_ok {
		http.respond_with_status(ctx.res, http.Status.Bad_Request)
		return
	}
	csrf_token := form_data["csrf_token"] or_else ""
	if !validate_session_csrf(&ctx.app.sessions, ctx.req, csrf_token) {
		http.respond_with_status(ctx.res, http.Status.Forbidden)
		return
	}

	switch ctx.action {
	case .Create, .Save:
		title := form_data["title"] or_else ""
		paste_body := form_data["body"] or_else ""
		defer {
			paste_wipe_string(title)
			paste_wipe_string(paste_body)
		}
		input := Paste_Input {title = title, body = paste_body}
		now_ms := paste_admin_now_ms()
		if validation_err := paste_store_validate_input(&ctx.app.pastes.store, input, now_ms); validation_err.kind != .None {
			form := Paste_Form_Data {
				GistId = ctx.gist_id,
				Revision = form_data["revision"] or_else "",
				Title = title,
				Body = paste_body,
				FormAction = "/admin/pastes/new" if ctx.action == .Create else fmt.tprintf("/admin/pastes/%s/save", ctx.gist_id),
				IsNew = ctx.action == .Create,
			}
			paste_admin_render_editor(
				ctx.app,
				ctx.req,
				ctx.res,
				form,
				validation_err.message,
				"",
				paste_admin_error_status(validation_err, true),
			)
			return
		}

		if ctx.action == .Create {
			loaded, create_err := paste_store_create(
				&ctx.app.pastes.store,
				input,
				now_ms,
				context.temp_allocator,
			)
			defer paste_loaded_destroy(&loaded, context.temp_allocator)
			if create_err.kind != .None {
				paste_admin_set_retry_after(ctx.res, create_err)
				error_message := create_err.message
				if create_err.kind == .Outcome_Unknown {
					error_message = "The remote create outcome is unknown. Refresh the paste list before trying again."
				}
				paste_admin_render_editor(
					ctx.app,
					ctx.req,
					ctx.res,
					Paste_Form_Data {
						Title = title,
						Body = paste_body,
						FormAction = "/admin/pastes/new",
						IsNew = true,
					},
					error_message,
					"",
					paste_admin_error_status(create_err),
				)
				return
			}
			location := fmt.tprintf("/admin/pastes/%s?notice=created", loaded.gist_id)
			http.headers_set(&ctx.res.headers, "Location", location)
			http.respond(ctx.res, http.Status.See_Other)
			return
		}

		revision := form_data["revision"] or_else ""
		if !paste_admin_revision_valid(revision) {
			paste_admin_render_editor(
				ctx.app,
				ctx.req,
				ctx.res,
				Paste_Form_Data {
					GistId = ctx.gist_id,
					Revision = revision,
					Title = title,
					Body = paste_body,
					FormAction = fmt.tprintf("/admin/pastes/%s/save", ctx.gist_id),
				},
				"Invalid or missing paste revision.",
				"",
				http.Status.Unprocessable_Content,
			)
			return
		}
		loaded, save_err := paste_store_update(
			&ctx.app.pastes.store,
			ctx.gist_id,
			revision,
			input,
			now_ms,
			context.temp_allocator,
		)
		defer paste_loaded_destroy(&loaded, context.temp_allocator)
		if save_err.kind != .None {
			paste_admin_set_retry_after(ctx.res, save_err)
			if save_err.kind == .Not_Found || save_err.kind == .Not_Ours {
				http.respond_with_status(ctx.res, http.Status.Not_Found)
				return
			}
			paste_admin_render_editor(
				ctx.app,
				ctx.req,
				ctx.res,
				Paste_Form_Data {
					GistId = ctx.gist_id,
					Revision = revision,
					Title = title,
					Body = paste_body,
					FormAction = fmt.tprintf("/admin/pastes/%s/save", ctx.gist_id),
				},
				save_err.message,
				"",
				paste_admin_error_status(save_err),
			)
			return
		}
		http.headers_set(
			&ctx.res.headers,
			"Location",
			fmt.tprintf("/admin/pastes/%s?notice=saved", ctx.gist_id),
		)
		http.respond(ctx.res, http.Status.See_Other)

	case .Rotate:
		revision := form_data["revision"] or_else ""
		if !paste_admin_revision_valid(revision) {
			http.respond_with_status(ctx.res, http.Status.Unprocessable_Content)
			return
		}
		loaded, rotate_err := paste_store_rotate(
			&ctx.app.pastes.store,
			ctx.gist_id,
			revision,
			context.temp_allocator,
		)
		defer paste_loaded_destroy(&loaded, context.temp_allocator)
		if rotate_err.kind != .None {
			paste_admin_set_retry_after(ctx.res, rotate_err)
			if rotate_err.kind == .Not_Found || rotate_err.kind == .Not_Ours {
				http.respond_with_status(ctx.res, http.Status.Not_Found)
				return
			}
			paste_admin_render_editor(
				ctx.app,
				ctx.req,
				ctx.res,
				Paste_Form_Data {
					GistId = ctx.gist_id,
					Revision = revision,
					FormAction = fmt.tprintf("/admin/pastes/%s/save", ctx.gist_id),
				},
				rotate_err.message,
				"",
				paste_admin_error_status(rotate_err),
			)
			return
		}
		http.headers_set(
			&ctx.res.headers,
			"Location",
			fmt.tprintf("/admin/pastes/%s?notice=rotated", ctx.gist_id),
		)
		http.respond(ctx.res, http.Status.See_Other)

	case .Delete:
		revision := form_data["revision"] or_else ""
		confirmation := form_data["confirmation"] or_else ""
		if !paste_admin_revision_valid(revision) || confirmation != "DELETE" {
			http.respond_with_status(ctx.res, http.Status.Unprocessable_Content)
			return
		}
		delete_err := paste_store_delete(&ctx.app.pastes.store, ctx.gist_id, revision)
		if delete_err.kind != .None {
			paste_admin_set_retry_after(ctx.res, delete_err)
			if delete_err.kind == .Not_Found || delete_err.kind == .Not_Ours {
				http.respond_with_status(ctx.res, http.Status.Not_Found)
				return
			}
			paste_admin_render_editor(
				ctx.app,
				ctx.req,
				ctx.res,
				Paste_Form_Data {
					GistId = ctx.gist_id,
					Revision = revision,
					FormAction = fmt.tprintf("/admin/pastes/%s/save", ctx.gist_id),
				},
				delete_err.message,
				"",
				paste_admin_error_status(delete_err),
			)
			return
		}
		http.headers_set(&ctx.res.headers, "Location", "/admin/pastes?notice=deleted")
		http.respond(ctx.res, http.Status.See_Other)
	}
}

paste_admin_create :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	paste_admin_begin_mutation(app_from_handler(handler), req, res, .Create)
}

paste_admin_save :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	gist_id := req.url_params[0] if len(req.url_params) == 1 else ""
	paste_admin_begin_mutation(app_from_handler(handler), req, res, .Save, gist_id)
}

paste_admin_rotate :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	gist_id := req.url_params[0] if len(req.url_params) == 1 else ""
	paste_admin_begin_mutation(app_from_handler(handler), req, res, .Rotate, gist_id)
}

paste_admin_delete :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	gist_id := req.url_params[0] if len(req.url_params) == 1 else ""
	paste_admin_begin_mutation(app_from_handler(handler), req, res, .Delete, gist_id)
}
