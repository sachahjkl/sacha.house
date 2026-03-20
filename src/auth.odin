package main

import "core:mem"
import "core:mem/virtual"
import "core:net"
import "core:sync"
import "core:time"
import "core:log"
import http "lib:odin-http"

Session :: struct {
	id:         string,
	created_at: time.Time,
	expires_at: time.Time,
}

Session_Storage :: struct {
	sessions:  map[string]Session,
	login_attempts: map[string]Login_Attempt,
	login_attempts_mu: sync.Mutex,
	arena:     virtual.Arena,
	allocator: mem.Allocator,
}

Login_Attempt :: struct {
	failed_count: int,
	blocked_until: time.Time,
}

Login_Attempt_Result :: enum {
	Invalid,
	Blocked,
	Authorized,
}

SESSION_EXPIRATION_TIME := 24 * time.Hour
SESSION_COOKIE_NAME := "session"
MAX_LOGIN_ATTEMPTS := 5
LOGIN_COOLDOWN := 30 * time.Second

session_storage: Session_Storage

init_sessions :: proc() -> mem.Allocator_Error {
	virtual.arena_init_growing(&session_storage.arena) or_return
	session_storage.allocator = virtual.arena_allocator(&session_storage.arena)
	session_storage.sessions = make(map[string]Session, allocator = session_storage.allocator)
	session_storage.login_attempts = make(map[string]Login_Attempt, allocator = session_storage.allocator)
	return .None
}

cleanup_sessions :: proc() {
	delete(session_storage.sessions)
	delete(session_storage.login_attempts)
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

get_login_attempt_key :: proc(req: ^http.Request) -> string {
	return net.address_to_string(req.client.address)
}

clear_login_attempt :: proc(req: ^http.Request) {
	key := get_login_attempt_key(req)
	sync.lock(&session_storage.login_attempts_mu)
	defer sync.unlock(&session_storage.login_attempts_mu)
	delete_key(&session_storage.login_attempts, key)
}

evaluate_login_attempt :: proc(req: ^http.Request, password: string) -> (result: Login_Attempt_Result, seconds_left: int) {
	key := get_login_attempt_key(req)
	now := time.now()

	sync.lock(&session_storage.login_attempts_mu)
	defer sync.unlock(&session_storage.login_attempts_mu)

	attempt, ok := session_storage.login_attempts[key]
	log.infof("Attempt: %v, ok: %v", attempt, ok)
	if !ok {
		attempt = Login_Attempt{}
	}

	remaining_seconds := time.duration_seconds(time.diff(now, attempt.blocked_until))
	log.infof("Remaining seconds: %d", remaining_seconds)
	if remaining_seconds > 0 {
		attempt.blocked_until = time.time_add(now, LOGIN_COOLDOWN)
		session_storage.login_attempts[key] = attempt
		return .Blocked, int(LOGIN_COOLDOWN / time.Second)
	}

	if password == get_admin_password() {
		delete_key(&session_storage.login_attempts, key)
		return .Authorized, 0
	}

	attempt.failed_count += 1
	if attempt.failed_count >= MAX_LOGIN_ATTEMPTS {
		attempt.failed_count = 0
		attempt.blocked_until = time.time_add(now, LOGIN_COOLDOWN)
		session_storage.login_attempts[key] = attempt
		return .Blocked, int(LOGIN_COOLDOWN / time.Second)
	}

	session_storage.login_attempts[key] = attempt
	return .Invalid, 0
}

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
