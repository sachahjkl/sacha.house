package main

import "core:mem"
import "core:mem/virtual"
import "core:time"
import http "lib:odin-http"

Session :: struct {
	id:         string,
	created_at: time.Time,
	expires_at: time.Time,
}

Session_Storage :: struct {
	sessions:  map[string]Session,
	arena:     virtual.Arena,
	allocator: mem.Allocator,
}

SESSION_EXPIRATION_TIME := 24 * time.Hour
SESSION_COOKIE_NAME := "session"

session_storage: Session_Storage

init_sessions :: proc() -> mem.Allocator_Error {
	virtual.arena_init_growing(&session_storage.arena) or_return
	session_storage.allocator = virtual.arena_allocator(&session_storage.arena)
	session_storage.sessions = make(map[string]Session, allocator = session_storage.allocator)
	return .None
}

cleanup_sessions :: proc() {
	delete(session_storage.sessions)
	virtual.arena_destroy(&session_storage.arena)
}

create_session :: proc() -> string {
	session_id := generate_id(allocator = session_storage.allocator)
	now := time.now()
	session_storage.sessions[session_id] = Session {
		id         = session_id,
		created_at = now,
		expires_at = time.time_add(now, SESSION_EXPIRATION_TIME),
	}
	return session_id
}

get_session_id_from_cookie :: proc(req: ^http.Request) -> (string, bool) {
	return http.request_cookie_get(req, SESSION_COOKIE_NAME)
}

is_session_expired :: proc(session: Session) -> bool {
	return time.diff(time.now(), session.expires_at) <= 0
}

set_session_cookie :: proc(res: ^http.Response, session_id: string) {
	cookie := http.Cookie {
		name         = SESSION_COOKIE_NAME,
		value        = session_id,
		path         = "/",
		http_only    = true,
		same_site    = .Strict,
		max_age_secs = int(SESSION_EXPIRATION_TIME / time.Second),
	}
	append(&res.cookies, cookie)
}

clear_session_cookie :: proc(res: ^http.Response) {
	cookie := http.Cookie {
		name         = SESSION_COOKIE_NAME,
		value        = "",
		path         = "/",
		http_only    = true,
		same_site    = .Strict,
		max_age_secs = 0,
	}
	append(&res.cookies, cookie)
}

Authorization_Result :: enum {
	Unauthorized,
	Authorized,
}

get_auth_level :: proc(req: ^http.Request, res: ^http.Response) -> Authorization_Result {
	session_id, ok := get_session_id_from_cookie(req)
	if !ok {
		return .Unauthorized
	}

	session, is_stored := session_storage.sessions[session_id]
	if !is_stored {
		return .Unauthorized
	}

	if is_session_expired(session) {
		// Session expired, remove it from storage and clear cookie
		delete_key(&session_storage.sessions, session.id)
		clear_session_cookie(res)
		return .Unauthorized
	}

	return .Authorized
}

get_admin_password :: proc() -> string {return APP_CONFIG.ADMIN_PASSWORD}

get_session :: proc(req: ^http.Request) -> Maybe(Session) {
	session_id, exists := get_session_id_from_cookie(req)
	if !exists {
		return nil
	}

	session, is_stored := session_storage.sessions[session_id]
	if !is_stored {
		return nil
	}

	return session
}

create_session_if_not_exists :: proc(req: ^http.Request, res: ^http.Response) -> string {
	session_id, exists := get_session_id_from_cookie(req)
	if exists {
		return session_id
	}
	return create_session()
}
