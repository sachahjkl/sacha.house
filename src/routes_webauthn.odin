package main

import "core:encoding/base64"
import "core:encoding/json"
import "core:log"
import "core:sort"
import "core:strings"

import http "lib:odin-http"
import temple "lib:temple"

Webauthn_Credential_Response :: struct {
	id:       string,
	label:    string,
	rawId:    string,
	response: struct {
		clientDataJSON:    string,
		attestationObject: string,
	},
	type: string,
}

Webauthn_Assertion_Response :: struct {
	id:       string,
	rawId:    string,
	response: struct {
		clientDataJSON:    string,
		authenticatorData: string,
		signature:         string,
		userHandle:        string,
	},
	type: string,
}

MAX_WEBAUTHN_REGISTRATION_BODY_BYTES :: 64 * 1024
MAX_WEBAUTHN_ASSERTION_BODY_BYTES :: 16 * 1024
MAX_PASSKEY_REMOVE_BODY_BYTES :: 4 * 1024

Passkey_List_Item :: struct {
	Id:    string,
	Label: string,
}

Passkey_List_Data :: struct {
	Passkeys: []Passkey_List_Item,
	CsrfToken: string,
}

admin_passkey_list_data :: proc(app: ^App_State, csrf_token: string) -> Passkey_List_Data {
	credentials := list_credentials(&app.webauthn, context.temp_allocator)
	sort.quick_sort_proc(credentials, proc(a, b: WebAuthn_Credential) -> int {
		return strings.compare(a.label, b.label)
	})
	passkeys := make([]Passkey_List_Item, len(credentials), context.temp_allocator)
	for cred, i in credentials {
		passkeys[i] = Passkey_List_Item{Id = cred.id, Label = cred.label}
	}
	return Passkey_List_Data{Passkeys = passkeys, CsrfToken = csrf_token}
}

render_admin_passkey_list :: proc(app: ^App_State, req: ^http.Request, res: ^http.Response) {
	http.headers_set(&res.headers, "Cache-Control", "no-store")
	csrf_storage: [SESSION_CSRF_TOKEN_BYTES]byte
	csrf_token, csrf_ok := session_csrf_token(&app.sessions, req, csrf_storage[:])
	if !csrf_ok {
		http.respond_with_status(res, http.Status.Unauthorized)
		return
	}
	defer wipe_session_csrf_token(csrf_token)
	template := temple.compiled("templates/_admin_passkey_list.temple.twig", Passkey_List_Data)
	render_page(req, res, template, admin_passkey_list_data(app, csrf_token))
}

admin_webauthn_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin(app, req, res, .RedirectLogin) {
		return
	}
	http.headers_set(&res.headers, "Cache-Control", "no-store")
	csrf_storage: [SESSION_CSRF_TOKEN_BYTES]byte
	csrf_token, csrf_ok := session_csrf_token(&app.sessions, req, csrf_storage[:])
	if !csrf_ok {
		http.respond_with_status(res, http.Status.Unauthorized)
		return
	}
	defer wipe_session_csrf_token(csrf_token)
	Page_Data :: struct {
		using base: Base_Page_Data,
		Passkeys:   Passkey_List_Data,
		CsrfToken: string,
	}
	data := Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data{title = "manage passkeys / sacha.house", description = "Manage WebAuthn passkeys."},
			req.url.path,
			true,
		),
		Passkeys = admin_passkey_list_data(app, csrf_token),
		CsrfToken = csrf_token,
	}
	page_template := temple.compiled("templates/admin_webauthn.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}

admin_webauthn_register_challenge :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin(app, req, res) {
		return
	}
	if !webauthn_configured(&app.config) {
		http.respond_plain(res, "WebAuthn is not configured", http.Status.Service_Unavailable)
		return
	}
	challenge_id := generate_id(&app.random_generator)
	challenge := generate_challenge()
	if !store_challenge(&app.webauthn, challenge_id, challenge, .Registration) {
		http.respond_plain(res, "Too many outstanding challenges", http.Status.Service_Unavailable)
		return
	}
	Challenge_Response :: struct {
		challenge: string,
		rp_id:     string,
		user_id:   string,
	}
	set_challenge_cookie(&app.config, req, res, challenge_id)
	http.respond_json(res, Challenge_Response {
		challenge = base64.encode(challenge, allocator = context.temp_allocator),
		rp_id = get_webauthn_rp_id(&app.config),
		user_id = "admin",
	}, http.Status.OK)
}

admin_webauthn_passkeys :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin(app, req, res) {
		return
	}
	render_admin_passkey_list(app, req, res)
}

admin_webauthn_register :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin_post(app, req, res) || !validate_admin_post_csrf_header(app, req, res) {
		return
	}
	if !webauthn_configured(&app.config) {
		http.respond_plain(res, "WebAuthn is not configured", http.Status.Service_Unavailable)
		return
	}
	challenge_id, ok := http.request_cookie_get(req, CHALLENGE_KEY)
	if !ok {
		http.respond_plain(res, "No challenge ID found", http.Status.Bad_Request)
		return
	}
	Context_Data :: struct {
		app:          ^App_State,
		req:          ^http.Request,
		res:          ^http.Response,
		challenge_id: string,
	}
	ctx := new_clone(Context_Data{app = app, req = req, res = res, challenge_id = challenge_id})
	http.body(req, MAX_WEBAUTHN_REGISTRATION_BODY_BYTES, ctx, proc(user_data: rawptr, body: http.Body, body_err: http.Body_Error) {
		ctx := cast(^Context_Data)user_data
		defer free(ctx)
		defer discard_challenge(&ctx.app.webauthn, ctx.challenge_id)
		clear_challenge_cookie(&ctx.app.config, ctx.req, ctx.res)
		if body_err != nil {
			http.respond(ctx.res, http.body_error_status(body_err))
			return
		}
		credential: Webauthn_Credential_Response
		if err := json.unmarshal(transmute([]byte)body, &credential, allocator = context.temp_allocator); err != nil {
			http.respond_plain(ctx.res, "Invalid JSON", http.Status.Bad_Request)
			return
		}
		challenge, client_err := verify_client_data_json(&ctx.app.config, credential.response.clientDataJSON, "webauthn.create")
		if client_err != .None {
			http.respond_plain(ctx.res, "Invalid WebAuthn client data", http.Status.Bad_Request)
			return
		}
		if !verify_and_consume_challenge(&ctx.app.webauthn, ctx.challenge_id, challenge, .Registration) {
			http.respond_plain(ctx.res, "Challenge verification failed", http.Status.Bad_Request)
			return
		}
		if credential.type != "public-key" || !verify_credential_binding(credential.id, credential.rawId) {
			http.respond_plain(ctx.res, "Credential binding failed", http.Status.Bad_Request)
			return
		}
		public_key, counter, attestation_err := verify_attestation_object(&ctx.app.config, credential.response.attestationObject, credential.rawId)
		if attestation_err == .Unsupported_Algorithm {
			http.respond_plain(ctx.res, "Unsupported credential algorithm", http.Status.Bad_Request)
			return
		}
		if attestation_err != .None {
			http.respond_plain(ctx.res, "Attestation verification failed", http.Status.Bad_Request)
			return
		}
		if !store_credential(&ctx.app.webauthn, credential.id, credential.label, public_key, counter) {
			http.respond_plain(ctx.res, "Could not persist credential", http.Status.Internal_Server_Error)
			return
		}
		http.respond_plain(ctx.res, "Registration successful", http.Status.OK)
	})
}

admin_webauthn_remove :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
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
	ctx := new_clone(Context_Data{app = app, req = req, res = res})
	http.body(req, MAX_PASSKEY_REMOVE_BODY_BYTES, ctx, proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
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
		credential_id := strings.trim_space(form_data["id"] or_else "")
		if credential_id == "" {
			http.respond_plain(ctx.res, "Missing credential id", http.Status.Bad_Request)
			return
		}
		if !remove_credential(&ctx.app.webauthn, credential_id) {
			http.respond_plain(ctx.res, "Unknown credential", http.Status.Not_Found)
			return
		}
		if _, is_htmx := http.headers_get(ctx.req.headers, "HX-Request"); is_htmx {
			render_admin_passkey_list(ctx.app, ctx.req, ctx.res)
			return
		}
		http.headers_set(&ctx.res.headers, "Location", "/admin/webauthn")
		http.respond(ctx.res, http.Status.See_Other)
	})
}

admin_webauthn_debug_challenge :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin(app, req, res) {
		return
	}
	if !webauthn_configured(&app.config) {
		http.respond_plain(res, "WebAuthn is not configured", http.Status.Service_Unavailable)
		return
	}
	if !has_credentials(&app.webauthn) {
		http.respond_plain(res, "No passkeys registered yet", http.Status.Bad_Request)
		return
	}
	Challenge_Response :: struct {
		challenge: string,
		rp_id:     string,
	}
	challenge := generate_challenge()
	http.respond_json(res, Challenge_Response {
		challenge = base64.encode(challenge, allocator = context.temp_allocator),
		rp_id = get_webauthn_rp_id(&app.config),
	}, http.Status.OK)
}

admin_webauthn_login_challenge :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !webauthn_configured(&app.config) {
		http.respond_plain(res, "WebAuthn is not configured", http.Status.Service_Unavailable)
		return
	}
	if !has_credentials(&app.webauthn) {
		http.respond_plain(res, "No passkeys registered yet", http.Status.Bad_Request)
		return
	}
	challenge_id := generate_id(&app.random_generator)
	challenge := generate_challenge()
	if !store_challenge(&app.webauthn, challenge_id, challenge, .Authentication) {
		http.respond_plain(res, "Too many outstanding challenges", http.Status.Service_Unavailable)
		return
	}
	Challenge_Response :: struct {
		challenge: string,
		rp_id:     string,
	}
	set_challenge_cookie(&app.config, req, res, challenge_id)
	http.respond_json(res, Challenge_Response {
		challenge = base64.encode(challenge, allocator = context.temp_allocator),
		rp_id = get_webauthn_rp_id(&app.config),
	}, http.Status.OK)
}

admin_webauthn_login :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !admin_request_same_origin(&app.config, req) {
		http.respond_with_status(res, http.Status.Forbidden)
		return
	}
	if !webauthn_configured(&app.config) {
		http.respond_plain(res, "WebAuthn is not configured", http.Status.Service_Unavailable)
		return
	}
	challenge_id, ok := http.request_cookie_get(req, CHALLENGE_KEY)
	if !ok {
		http.respond_plain(res, "No challenge ID found", http.Status.Bad_Request)
		return
	}
	Context_Data :: struct {
		app:          ^App_State,
		req:          ^http.Request,
		res:          ^http.Response,
		challenge_id: string,
	}
	ctx := new_clone(Context_Data{app = app, req = req, res = res, challenge_id = challenge_id})
	http.body(req, MAX_WEBAUTHN_ASSERTION_BODY_BYTES, ctx, proc(user_data: rawptr, body: http.Body, body_err: http.Body_Error) {
		ctx := cast(^Context_Data)user_data
		defer free(ctx)
		defer discard_challenge(&ctx.app.webauthn, ctx.challenge_id)
		clear_challenge_cookie(&ctx.app.config, ctx.req, ctx.res)
		if body_err != nil {
			http.respond(ctx.res, http.body_error_status(body_err))
			return
		}
		assertion: Webauthn_Assertion_Response
		if err := json.unmarshal(transmute([]byte)body, &assertion, allocator = context.temp_allocator); err != nil {
			http.respond_plain(ctx.res, "Invalid JSON", http.Status.Bad_Request)
			return
		}
		challenge, client_err := verify_client_data_json(&ctx.app.config, assertion.response.clientDataJSON, "webauthn.get")
		if client_err != .None {
			http.respond_plain(ctx.res, "Invalid WebAuthn client data", http.Status.Unauthorized)
			return
		}
		if !verify_and_consume_challenge(&ctx.app.webauthn, ctx.challenge_id, challenge, .Authentication) {
			http.respond_plain(ctx.res, "Challenge verification failed", http.Status.Unauthorized)
			return
		}
		if assertion.type != "public-key" ||
		   !verify_credential_binding(assertion.id, assertion.rawId) ||
		   !verify_user_handle(assertion.response.userHandle) {
			http.respond_plain(ctx.res, "Credential binding failed", http.Status.Unauthorized)
			return
		}
		verification_err := verify_assertion_signature(
			&ctx.app.webauthn,
			&ctx.app.config,
			assertion.id,
			assertion.response.authenticatorData,
			assertion.response.clientDataJSON,
			assertion.response.signature,
		)
		if verification_err == .Unsupported_Algorithm {
			http.respond_plain(ctx.res, "Unsupported credential algorithm", http.Status.Unauthorized)
			return
		}
		if verification_err != .None {
			http.respond_plain(ctx.res, "Assertion verification failed", http.Status.Unauthorized)
			return
		}
		session_id, session_ok := create_session(&ctx.app.sessions, &ctx.app.random_generator)
		if !session_ok {
			http.respond_with_status(ctx.res, http.Status.Service_Unavailable)
			return
		}
		set_session_cookie(&ctx.app.config, ctx.req, ctx.res, session_id)
		http.respond_plain(ctx.res, "Login successful", http.Status.OK)
	})
}
