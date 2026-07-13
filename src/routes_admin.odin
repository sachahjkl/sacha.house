package main

import "core:fmt"
import "core:log"
import "core:net"

import http "lib:odin-http"
import temple "lib:temple"

MAX_PASSWORD_LOGIN_BODY_BYTES :: 8 * 1024
MAX_ADMIN_ACTION_BODY_BYTES :: 4 * 1024

ensure_admin_post :: proc(app: ^App_State, req: ^http.Request, res: ^http.Response) -> bool {
	if !ensure_admin(app, req, res) {
		return false
	}
	if !admin_request_same_origin(&app.config, req) {
		http.respond_with_status(res, http.Status.Forbidden)
		return false
	}
	return true
}

validate_admin_post_csrf :: proc(
	app: ^App_State,
	req: ^http.Request,
	res: ^http.Response,
	token: string,
) -> bool {
	if validate_session_csrf(&app.sessions, req, token) {
		return true
	}
	http.respond_with_status(res, http.Status.Forbidden)
	return false
}

validate_admin_post_csrf_header :: proc(
	app: ^App_State,
	req: ^http.Request,
	res: ^http.Response,
) -> bool {
	return validate_admin_post_csrf(
		app,
		req,
		res,
		http.headers_get(req.headers, "X-CSRF-Token") or_else "",
	)
}

admin_login_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if get_auth_level(&app.sessions, &app.config, req, res) == .Authorized {
		http.headers_set(&res.headers, "Location", "/admin")
		http.respond(res, http.Status.Temporary_Redirect)
		return
	}
	Page_Data :: struct {
		using base: Base_Page_Data,
		Error:      string,
	}
	data := Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data{title = "admin login / sacha.house", description = "Admin login."},
			req.url.path,
			false,
		),
		Error = "",
	}
	page_template := temple.compiled("templates/admin_login.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}

admin_login_submit :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !admin_request_same_origin(&app.config, req) {
		http.respond_with_status(res, http.Status.Forbidden)
		return
	}
	Login_Form_Data :: struct {
		Error: string,
	}
	Context_Data :: struct {
		app:           ^App_State,
		res:           ^http.Response,
		req:           ^http.Request,
		form_template: temple.Compiled(Login_Form_Data),
	}
	form_template := temple.compiled("templates/_login_form.temple.twig", Login_Form_Data)
	ctx := new_clone(Context_Data{app = app, res = res, req = req, form_template = form_template})
	http.body(
		req,
		MAX_PASSWORD_LOGIN_BODY_BYTES,
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
			password := form_data["password"] or_else ""
			if result, seconds_left := evaluate_login_attempt(
				&ctx.app.sessions,
				&ctx.app.config,
				ctx.req,
				password,
				ctx.app.options.hot_reload,
			); result == .Authorized {
				session_id, session_ok := create_session(&ctx.app.sessions, &ctx.app.random_generator)
				if !session_ok {
					http.respond_with_status(ctx.res, http.Status.Service_Unavailable)
					return
				}
				set_session_cookie(&ctx.app.config, ctx.req, ctx.res, session_id)
				if _, is_htmx := http.headers_get(ctx.req.headers, "HX-Request"); is_htmx {
					http.headers_set(&ctx.res.headers, "HX-Redirect", "/admin")
					http.respond_with_status(ctx.res, http.Status.OK)
				} else {
					http.headers_set(&ctx.res.headers, "Location", "/admin")
					http.respond(ctx.res, http.Status.See_Other)
				}
			} else if result == .Blocked {
				render_page(
					ctx.req,
					ctx.res,
					ctx.form_template,
					Login_Form_Data {
						Error = fmt.tprintf(
							"Too many failed attempts. Try again in %d second(s).",
							seconds_left,
						),
					},
				)
			} else {
				render_page(
					ctx.req,
					ctx.res,
					ctx.form_template,
					Login_Form_Data{Error = "Invalid password"},
				)
			}
		},
	)
}

admin_logout :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin_post(app, req, res) {
		return
	}
	Context_Data :: struct {
		app: ^App_State,
		req: ^http.Request,
		res: ^http.Response,
	}
	ctx := new_clone(Context_Data {app = app, req = req, res = res})
	http.body(req, MAX_ADMIN_ACTION_BODY_BYTES, ctx, proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
		ctx := cast(^Context_Data)user_data
		defer free(ctx)
		if err != nil {
			http.respond(ctx.res, http.body_error_status(err))
			return
		}
		defer paste_wipe_string(string(body))
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
		revoke_session(&ctx.app.sessions, ctx.req)
		clear_session_cookie(&ctx.app.config, ctx.req, ctx.res)
		http.headers_set(&ctx.res.headers, "HX-Redirect", "/admin/login")
		http.headers_set(&ctx.res.headers, "Location", "/admin/login")
		http.respond(ctx.res, http.Status.See_Other)
	})
}

admin_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin(app, req, res, .RedirectLogin) {
		return
	}
	Page_Data :: struct {
		using base:    Base_Page_Data,
		IpAddress:     string,
		ProfileData:   string,
		PasteEnabled:  bool,
		CsrfToken:    string,
	}
	profile_json := ""
	if embedded := get_embedded_profile_string(&app.static); embedded != nil {
		profile_json = embedded.(string)
	}
	http.headers_set(&res.headers, "Cache-Control", "no-store")
	csrf_storage: [SESSION_CSRF_TOKEN_BYTES]byte
	csrf_token, csrf_ok := session_csrf_token(&app.sessions, req, csrf_storage[:])
	if !csrf_ok {
		http.respond_with_status(res, http.Status.Unauthorized)
		return
	}
	defer wipe_session_csrf_token(csrf_token)
	data := Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data{title = "admin / sacha.house", description = "Admin panel."},
			req.url.path,
			true,
		),
		IpAddress = net.address_to_string(req.client.address),
		ProfileData = profile_json,
		PasteEnabled = app.pastes.enabled,
		CsrfToken = csrf_token,
	}
	page_template := temple.compiled("templates/admin.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}
