package main

import "core:encoding/base64"
import "core:strings"
import http "odin-http"

// NOTE(sachahjkl):
// Basic auth challenge for the admin panel per MDN.
// - Parse `Authorization: Basic base64(user:pass)`
// - Compare to configured credentials from config file
is_authorized :: proc(req: ^http.Request) -> bool {
	auth_header := http.headers_get(req.headers, "Authorization") or_else ""
	if auth_header == "" {
		return false
	}

	if !strings.has_prefix(auth_header, "Basic ") {
		return false
	}

	encoded := auth_header[6:]
	decoded, err := base64.decode(encoded, allocator = context.temp_allocator)
	if err != nil {
		return false
	}

	creds := string(decoded)
	sep := strings.index(creds, ":")
	if sep == -1 {
		return false
	}

	username := creds[:sep]
	password := creds[sep + 1:]

	return username == get_admin_username() && password == get_admin_password()
}

require_auth :: proc(res: ^http.Response) {
	http.headers_set(&res.headers, "WWW-Authenticate", `Basic realm="Admin Panel"`)
	http.respond_with_status(res, http.Status.Unauthorized)
}

get_admin_username :: proc() -> string {return APP_CONFIG.ADMIN_USERNAME}
get_admin_password :: proc() -> string {return APP_CONFIG.ADMIN_PASSWORD}
