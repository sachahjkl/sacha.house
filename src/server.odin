package main

import "core:fmt"
import "core:log"
import "core:net"

import http "lib:odin-http"

app_handler :: proc(app: ^App_State, handle: http.Handler_Proc) -> http.Handler {
	return http.Handler {
		user_data = app,
		handle = handle,
	}
}

app_from_handler :: proc(handler: ^http.Handler) -> ^App_State {
	return cast(^App_State)handler.user_data
}

security_headers :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	http.headers_set(
		&res.headers,
		"Content-Security-Policy",
		"default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://fonts.cdnfonts.com; font-src 'self' https://fonts.gstatic.com https://fonts.cdnfonts.com; img-src 'self' data: https:; connect-src 'self'; worker-src 'self'; manifest-src 'self'",
	)
	http.headers_set(&res.headers, "X-Content-Type-Options", "nosniff")
	http.headers_set(&res.headers, "Referrer-Policy", "strict-origin-when-cross-origin")
	http.headers_set(
		&res.headers,
		"Permissions-Policy",
		"accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()",
	)
	if app.config.TRUST_PROXY_HTTPS {
		http.headers_set(&res.headers, "Strict-Transport-Security", "max-age=31536000; includeSubDomains")
	}
	next := handler.next.(^http.Handler)
	next.handle(next, req, res)
}

server_start :: proc(app: ^App_State) {
	s: http.Server
	http.server_shutdown_on_interrupt(&s)

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)
	log.info("Initializing routes...")

	// Routes are tried in order. Specific routes must stay before captured and fallback routes.
	http.route_get(&router, "/static/(.*)", app_handler(app, serve_static_file))
	http.route_get(&router, "/media/blog/([%w-]+)/assets/(.*)", app_handler(app, blog_media_file))
	http.route_get(&router, "/", app_handler(app, index_page))
	http.route_get(&router, "/ping", app_handler(app, ping))
	http.route_get(&router, "/blog", app_handler(app, blog_page))
	http.route_get(&router, "/blog/rss.xml", app_handler(app, blog_rss_feed))
	http.route_get(&router, "/blog/atom.xml", app_handler(app, blog_atom_feed))
	http.route_get(&router, "/blog/([%w-]+)", app_handler(app, blog_post_page))
	http.route_get(&router, "/about", app_handler(app, about_page))
	http.route_get(&router, "/projects", app_handler(app, projects_page))
	http.route_get(&router, "/debug/logo", app_handler(app, debug_logo_page))
	http.route_get(&router, "/ip", app_handler(app, ip_page))
	http.route_get(&router, "/api/ip", app_handler(app, ip_api))
	http.route_get(&router, "/teapot", app_handler(app, teapot_page))
	http.route_get(&router, "/admin/login", app_handler(app, admin_login_page))
	http.route_post(&router, "/admin/login", app_handler(app, admin_login_submit))
	http.route_post(&router, "/admin/logout", app_handler(app, admin_logout))
	http.route_get(&router, "/admin", app_handler(app, admin_page))
	http.route_get(&router, "/admin/blogposts", app_handler(app, admin_blogposts_page))
	http.route_get(&router, "/admin/webauthn", app_handler(app, admin_webauthn_page))
	http.route_get(&router, "/admin/pastes", app_handler(app, paste_admin_list_page))
	if app.pastes.enabled {
		http.route_get(&router, "/admin/pastes/new", app_handler(app, paste_admin_new_page))
		http.route_post(&router, "/admin/pastes/new", app_handler(app, paste_admin_create))
		http.route_get(
			&router,
			"/admin/pastes/([%da-fA-F]+)",
			app_handler(app, paste_admin_edit_page),
		)
		http.route_post(
			&router,
			"/admin/pastes/([%da-fA-F]+)/save",
			app_handler(app, paste_admin_save),
		)
		http.route_post(
			&router,
			"/admin/pastes/([%da-fA-F]+)/rotate",
			app_handler(app, paste_admin_rotate),
		)
		http.route_post(
			&router,
			"/admin/pastes/([%da-fA-F]+)/delete",
			app_handler(app, paste_admin_delete),
		)
	}
	http.route_get(&router, "/admin/blogposts/new", app_handler(app, admin_blogpost_new_page))
	http.route_post(&router, "/admin/blogposts/new", app_handler(app, admin_blogpost_create))
	http.route_post(
		&router,
		"/admin/blogposts/upload%-image",
		app_handler(app, admin_blogpost_upload_image),
	)
	http.route_post(&router, "/admin/blogposts/([%w-]+)/save", app_handler(app, admin_blogpost_save))
	http.route_get(&router, "/admin/blogposts/([%w-]+)", app_handler(app, admin_blogpost_edit_page))
	http.route_get(
		&router,
		"/admin/webauthn/register%-challenge",
		app_handler(app, admin_webauthn_register_challenge),
	)
	http.route_get(&router, "/admin/webauthn/passkeys", app_handler(app, admin_webauthn_passkeys))
	http.route_post(&router, "/admin/webauthn/register", app_handler(app, admin_webauthn_register))
	http.route_post(&router, "/admin/webauthn/remove", app_handler(app, admin_webauthn_remove))
	http.route_get(
		&router,
		"/admin/webauthn/debug%-challenge",
		app_handler(app, admin_webauthn_debug_challenge),
	)
	http.route_get(
		&router,
		"/admin/webauthn/login%-challenge",
		app_handler(app, admin_webauthn_login_challenge),
	)
	http.route_post(&router, "/admin/webauthn/login", app_handler(app, admin_webauthn_login))
	http.route_post(&router, "/admin/refresh%-projects", app_handler(app, admin_refresh_projects))

	// Fallback to embedded assets served from the site root.
	http.route_get(&router, "/(.*)", app_handler(app, serve_static_file))
	log.info("Routes initialized.")

	routed := http.router_handler(&router)
	secured := http.middleware_proc(&routed, security_headers)
	secured.user_data = app
	listen_endpoint := net.Endpoint {
		address = net.IP4_Any,
		port = int(app.options.port),
	}
	log.infof("Listening on http://localhost:%d", listen_endpoint.port)
	err := http.listen_and_serve(&s, secured, listen_endpoint)
	fmt.assertf(err == nil, "server stopped with error: %v", err)
}
