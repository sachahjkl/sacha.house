package main

import "core:crypto"
import "core:crypto/argon2id"
import "core:encoding/base64"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:net"
import "core:strconv"
import "core:strings"
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

get_admin_password_hash :: proc() -> string { return APP_CONFIG.ADMIN_PASSWORD_HASH }

get_password_salt :: proc() -> string { return APP_CONFIG.PASSWORD_SALT }

hash_password :: proc(password: string, allocator := context.allocator) -> (string, bool) {
	salt: [argon2id.RECOMMENDED_SALT_SIZE]byte
	crypto.rand_bytes(salt[:])

	tag_size := argon2id.RECOMMENTED_TAG_SIZE
	tag := make([]u8, tag_size, allocator = allocator)
	defer delete(tag)

	secret := transmute([]u8)(get_password_salt())

	err := argon2id.derive(&argon2id.PARAMS_OWASP,
		transmute([]u8)(password),
		salt[:],
		tag,
		secret,
	)
	if err != .None {
		return "", false
	}

	salt_b64, ok1 := base64.encode(salt[:], allocator = allocator)
	if ok1 != .None { return "", false }
	defer delete(salt_b64)
	tag_b64, ok2 := base64.encode(tag, allocator = allocator)
	if ok2 != .None { return "", false }
	defer delete(tag_b64)

	p := &argon2id.PARAMS_OWASP
	params_str := fmt.tprintf("m=%d,t=%d,p=%d", p.memory_size, p.passes, p.parallelism)

	result := fmt.aprintf(
		"$argon2id$v=19$%s$%s$%s",
		params_str,
		salt_b64,
		tag_b64,
		allocator = allocator,
	)
	return result, true
}

parse_argon2_hash :: proc(hash_str: string, allocator := context.allocator) -> (salt: []u8, tag: []u8, params: argon2id.Parameters, ok: bool) {
	if !strings.has_prefix(hash_str, "$argon2id$v=19$") {
		return nil, nil, argon2id.Parameters{}, false
	}

	rest := hash_str[len("$argon2id$v=19$"):]
	parts := strings.split(rest, "$", allocator = allocator)
	defer delete(parts)

	if len(parts) != 3 {
		return nil, nil, argon2id.Parameters{}, false
	}

	params_str := parts[0]
	salt_b64 := parts[1]
	tag_b64 := parts[2]

	params = argon2id.PARAMS_OWASP

	param_parts := strings.split(params_str, ",", allocator = allocator)
	defer delete(param_parts)
	for part in param_parts {
		kv := strings.split_n(part, "=", 2, allocator = allocator)
		defer delete(kv)
		if len(kv) != 2 { continue }

		val, parse_ok := strconv.parse_int(kv[1])
		if !parse_ok { continue }

		if strings.has_prefix(kv[0], "m") {
			params.memory_size = u32(val)
		} else if strings.has_prefix(kv[0], "t") {
			params.passes = u32(val)
		} else if strings.has_prefix(kv[0], "p") {
			params.parallelism = u32(val)
		}
	}

	salt_bytes, salt_ok := base64.decode(salt_b64, allocator = allocator)
	if salt_ok != .None { return nil, nil, argon2id.Parameters{}, false }
	defer delete(salt_bytes)

	tag_bytes, tag_ok := base64.decode(tag_b64, allocator = allocator)
	if tag_ok != .None { return nil, nil, argon2id.Parameters{}, false }
	defer delete(tag_bytes)

	salt_out := make([]u8, len(salt_bytes), allocator = allocator)
	copy(salt_out, salt_bytes)

	tag_out := make([]u8, len(tag_bytes), allocator = allocator)
	copy(tag_out, tag_bytes)

	return salt_out, tag_out, params, true
}

verify_password :: proc(password: string, hash_str: string, allocator := context.allocator) -> bool {
	if hash_str == "" || get_password_salt() == "" {
		return false
	}

	salt, expected_tag, params, ok := parse_argon2_hash(hash_str, allocator)
	if !ok { return false }
	defer delete(salt)
	defer delete(expected_tag)

	tag_size := len(expected_tag)
	actual_tag := make([]u8, tag_size, allocator = allocator)
	defer delete(actual_tag)

	secret := transmute([]u8)(get_password_salt())

	err := argon2id.derive(&params,
		transmute([]u8)(password),
		salt,
		actual_tag,
		secret,
	)
	if err != .None { return false }

	return crypto.compare_constant_time(actual_tag, expected_tag) == 1
}

is_admin_password_configured :: proc() -> bool {
	return get_admin_password_hash() != "" && get_password_salt() != ""
}

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

	remaining_seconds := int(time.duration_seconds(time.diff(now, attempt.blocked_until)))
	log.infof("Remaining seconds: %d", remaining_seconds)
	if remaining_seconds > 0 {
		attempt.blocked_until = time.time_add(now, LOGIN_COOLDOWN)
		session_storage.login_attempts[key] = attempt
		return .Blocked, int(LOGIN_COOLDOWN / time.Second)
	}

	if is_admin_password_configured() && verify_password(password, get_admin_password_hash()) {
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
