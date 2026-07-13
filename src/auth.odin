package main

import "core:crypto"
import "core:crypto/argon2id"
import "core:encoding/base64"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:net"
import "core:strconv"
import "core:math/rand"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"
import http "lib:odin-http"

Session :: struct {
	id:          string,
	created_at:  time.Time,
	expires_at:  time.Time,
	csrf_secret: [32]byte,
}

Session_Storage :: struct {
	sessions:          map[string]^Session,
	sessions_mu:       sync.Mutex,
	login_attempts:    map[string]Login_Attempt,
	login_attempts_mu: sync.Mutex,
	allocator:         mem.Allocator,
}

Login_Attempt :: struct {
	failed_count: int,
	blocked_until: time.Time,
	last_seen:     time.Time,
}

Login_Attempt_Result :: enum {
	Invalid,
	Blocked,
	Authorized,
}

SESSION_EXPIRATION_TIME :: 24 * time.Hour
SESSION_COOKIE_NAME :: "session"
MAX_LOGIN_ATTEMPTS :: 5
LOGIN_COOLDOWN :: 30 * time.Second
MAX_SESSION_COUNT :: 1024
MAX_LOGIN_ATTEMPT_COUNT :: 2048
LOGIN_ATTEMPT_RETENTION :: 30 * time.Minute
SESSION_CSRF_SECRET_BYTES :: 32
SESSION_CSRF_TOKEN_BYTES  :: SESSION_CSRF_SECRET_BYTES * 2

session_storage_init :: proc(storage: ^Session_Storage, allocator: mem.Allocator) -> mem.Allocator_Error {
	storage.allocator = allocator
	storage.sessions = make(map[string]^Session, allocator)
	storage.login_attempts = make(map[string]Login_Attempt, allocator)
	return .None
}

session_storage_destroy :: proc(storage: ^Session_Storage) {
	if storage == nil {
		return
	}
	for _, session in storage.sessions {
		session_destroy(session, storage.allocator)
	}
	for key in storage.login_attempts {
		delete(key, storage.allocator)
	}
	delete(storage.sessions)
	delete(storage.login_attempts)
	storage^ = {}
}

session_destroy :: proc(session: ^Session, allocator: mem.Allocator) {
	if session == nil {
		return
	}
	crypto.zero_explicit(raw_data(session.csrf_secret[:]), len(session.csrf_secret))
	delete(session.id, allocator)
	free(session, allocator)
}

remove_session_locked :: proc(storage: ^Session_Storage, session_id: string) {
	session, ok := storage.sessions[session_id]
	if !ok || session == nil do return
	delete_key(&storage.sessions, session_id)
	session_destroy(session, storage.allocator)
}

prune_sessions_locked :: proc(storage: ^Session_Storage, now: time.Time) {
	expired: [MAX_SESSION_COUNT]string
	expired_count := 0
	for id, session in storage.sessions {
		if session == nil || time.diff(now, session.expires_at) <= 0 {
			expired[expired_count] = id
			expired_count += 1
		}
	}
	for id in expired[:expired_count] {
		remove_session_locked(storage, id)
	}
}

create_session :: proc(storage: ^Session_Storage, generator: ^rand.Generator) -> (string, bool) {
	sync.lock(&storage.sessions_mu)
	defer sync.unlock(&storage.sessions_mu)
	now := time.now()
	prune_sessions_locked(storage, now)
	if len(storage.sessions) >= MAX_SESSION_COUNT do return "", false
	session_id := generate_id(generator, allocator = storage.allocator)
	if session_id == "" do return "", false
	if _, collision := storage.sessions[session_id]; collision {
		delete(session_id, storage.allocator)
		return "", false
	}
	session, alloc_err := new(Session, storage.allocator)
	if alloc_err != .None {
		delete(session_id, storage.allocator)
		return "", false
	}
	session.id = session_id
	session.created_at = now
	session.expires_at = time.time_add(now, SESSION_EXPIRATION_TIME)
	crypto.rand_bytes(session.csrf_secret[:])
	storage.sessions[session_id] = session
	return session_id, true
}

get_session_id_from_cookie :: proc(req: ^http.Request) -> (string, bool) {
	session_id, ok := http.request_cookie_get(req, SESSION_COOKIE_NAME)
	return session_id, ok && len(session_id) == 36
}

is_session_expired :: proc(session: ^Session) -> bool {
	return session == nil || time.diff(time.now(), session.expires_at) <= 0
}

auth_cookie_secure :: proc(config: ^Config, req: ^http.Request) -> bool {
	if strings.has_prefix(config.WEBAUTHN_ORIGIN, "https://") {
		return true
	}
	if !config.TRUST_PROXY_HTTPS {
		return false
	}
	forwarded_proto := strings.trim_space(http.headers_get(req.headers, "X-Forwarded-Proto") or_else "")
	return forwarded_proto == "https"
}

admin_request_same_origin :: proc(config: ^Config, req: ^http.Request) -> bool {
	origin := strings.trim_space(http.headers_get(req.headers, "Origin") or_else "")
	host := strings.trim_space(http.headers_get(req.headers, "Host") or_else "")
	if origin == "" || host == "" {
		return false
	}
	prefix := "https://" if auth_cookie_secure(config, req) else "http://"
	return len(origin) == len(prefix) + len(host) &&
		strings.has_prefix(origin, prefix) &&
		strings.equal_fold(origin[len(prefix):], host)
}

set_session_cookie :: proc(config: ^Config, req: ^http.Request, res: ^http.Response, session_id: string) {
	append(&res.cookies, http.Cookie {
		name = SESSION_COOKIE_NAME,
		value = session_id,
		path = "/",
		http_only = true,
		secure = auth_cookie_secure(config, req),
		same_site = .Strict,
		max_age_secs = int(SESSION_EXPIRATION_TIME / time.Second),
	})
}

clear_session_cookie :: proc(config: ^Config, req: ^http.Request, res: ^http.Response) {
	append(&res.cookies, http.Cookie {
		name = SESSION_COOKIE_NAME,
		value = "",
		path = "/",
		http_only = true,
		secure = auth_cookie_secure(config, req),
		same_site = .Strict,
		max_age_secs = 0,
	})
}

Authorization_Result :: enum {
	Unauthorized,
	Authorized,
}

get_auth_level :: proc(storage: ^Session_Storage, config: ^Config, req: ^http.Request, res: ^http.Response) -> Authorization_Result {
	session_id, ok := get_session_id_from_cookie(req)
	if !ok do return .Unauthorized
	sync.lock(&storage.sessions_mu)
	defer sync.unlock(&storage.sessions_mu)
	session, stored := storage.sessions[session_id]
	if !stored || session == nil do return .Unauthorized
	if is_session_expired(session) {
		remove_session_locked(storage, session.id)
		clear_session_cookie(config, req, res)
		return .Unauthorized
	}
	return .Authorized
}

session_csrf_hex_nibble :: proc(c: byte) -> (byte, bool) {
	switch c {
	case '0'..='9': return c - '0', true
	case 'a'..='f': return c - 'a' + 10, true
	case: return 0, false
	}
}

session_csrf_token :: proc(
	storage: ^Session_Storage,
	req: ^http.Request,
	dst: []byte,
) -> (string, bool) {
	if storage == nil || req == nil || len(dst) < SESSION_CSRF_TOKEN_BYTES {
		return "", false
	}
	session_id, ok := get_session_id_from_cookie(req)
	if !ok {
		return "", false
	}
	sync.lock(&storage.sessions_mu)
	defer sync.unlock(&storage.sessions_mu)
	session, stored := storage.sessions[session_id]
	if !stored || is_session_expired(session) {
		if stored {
			remove_session_locked(storage, session_id)
		}
		return "", false
	}
	hex := "0123456789abcdef"
	for value, i in session.csrf_secret {
		dst[i * 2] = hex[value >> 4]
		dst[i * 2 + 1] = hex[value & 0x0f]
	}
	return string(dst[:SESSION_CSRF_TOKEN_BYTES]), true
}

validate_session_csrf :: proc(
	storage: ^Session_Storage,
	req: ^http.Request,
	token: string,
) -> bool {
	if storage == nil || req == nil || len(token) != SESSION_CSRF_TOKEN_BYTES {
		return false
	}
	decoded: [SESSION_CSRF_SECRET_BYTES]byte
	defer crypto.zero_explicit(raw_data(decoded[:]), len(decoded))
	for i in 0..<SESSION_CSRF_SECRET_BYTES {
		hi, hi_ok := session_csrf_hex_nibble(token[i * 2])
		lo, lo_ok := session_csrf_hex_nibble(token[i * 2 + 1])
		if !hi_ok || !lo_ok {
			return false
		}
		decoded[i] = hi << 4 | lo
	}
	session_id, ok := get_session_id_from_cookie(req)
	if !ok {
		return false
	}
	sync.lock(&storage.sessions_mu)
	defer sync.unlock(&storage.sessions_mu)
	session, stored := storage.sessions[session_id]
	if !stored || is_session_expired(session) {
		if stored {
			remove_session_locked(storage, session_id)
		}
		return false
	}
	return crypto.compare_constant_time(session.csrf_secret[:], decoded[:]) == 1
}

wipe_session_csrf_token :: proc(token: string) {
	if token != "" {
		crypto.zero_explicit(raw_data(transmute([]byte)token), len(token))
	}
}

get_admin_password_hash :: proc(config: ^Config) -> string { return config.ADMIN_PASSWORD_HASH }

get_password_salt :: proc(config: ^Config) -> string { return config.PASSWORD_SALT }

hash_password :: proc(config: ^Config, password: string, allocator := context.allocator) -> (string, bool) {
	salt: [argon2id.RECOMMENDED_SALT_SIZE]byte
	crypto.rand_bytes(salt[:])

	tag_size := argon2id.RECOMMENTED_TAG_SIZE
	tag := make([]u8, tag_size, allocator = allocator)
	defer delete(tag)

	secret := transmute([]u8)(get_password_salt(config))

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

verify_password :: proc(config: ^Config, password: string, hash_str: string, allocator := context.allocator) -> bool {
	if hash_str == "" || get_password_salt(config) == "" {
		return false
	}

	salt, expected_tag, params, ok := parse_argon2_hash(hash_str, allocator)
	if !ok { return false }
	defer delete(salt)
	defer delete(expected_tag)

	tag_size := len(expected_tag)
	actual_tag := make([]u8, tag_size, allocator = allocator)
	defer delete(actual_tag)

	secret := transmute([]u8)(get_password_salt(config))

	err := argon2id.derive(&params,
		transmute([]u8)(password),
		salt,
		actual_tag,
		secret,
	)
	if err != .None { return false }

	return crypto.compare_constant_time(actual_tag, expected_tag) == 1
}

is_admin_password_configured :: proc(config: ^Config) -> bool {
	return get_admin_password_hash(config) != "" && get_password_salt(config) != ""
}

get_login_attempt_key :: proc(req: ^http.Request) -> string {
	return net.address_to_string(req.client.address)
}

remove_login_attempt_locked :: proc(storage: ^Session_Storage, key: string) {
	if _, ok := storage.login_attempts[key]; !ok do return
	stored_key, _ := delete_key(&storage.login_attempts, key)
	delete(stored_key, storage.allocator)
}

prune_login_attempts_locked :: proc(storage: ^Session_Storage, now: time.Time) {
	expired: [MAX_LOGIN_ATTEMPT_COUNT]string
	expired_count := 0
	for key, attempt in storage.login_attempts {
		if time.diff(attempt.last_seen, now) > LOGIN_ATTEMPT_RETENTION {
			expired[expired_count] = key
			expired_count += 1
		}
	}
	for key in expired[:expired_count] {
		remove_login_attempt_locked(storage, key)
	}
}

clear_login_attempt :: proc(storage: ^Session_Storage, req: ^http.Request) {
	key := get_login_attempt_key(req)
	sync.lock(&storage.login_attempts_mu)
	defer sync.unlock(&storage.login_attempts_mu)
	remove_login_attempt_locked(storage, key)
}

evaluate_login_attempt :: proc(
	storage: ^Session_Storage,
	config: ^Config,
	req: ^http.Request,
	password: string,
	allow_unconfigured_dev_login := false,
) -> (result: Login_Attempt_Result, seconds_left: int) {
	if allow_unconfigured_dev_login && get_admin_password_hash(config) == "" {
		return .Authorized, 0
	}
	key := get_login_attempt_key(req)
	now := time.now()
	sync.lock(&storage.login_attempts_mu)
	defer sync.unlock(&storage.login_attempts_mu)
	prune_login_attempts_locked(storage, now)
	attempt, ok := storage.login_attempts[key]
	if !ok {
		if len(storage.login_attempts) >= MAX_LOGIN_ATTEMPT_COUNT {
			return .Blocked, int(LOGIN_COOLDOWN / time.Second)
		}
		attempt = Login_Attempt{}
	}
	remaining_seconds := int(time.duration_seconds(time.diff(now, attempt.blocked_until)))
	if remaining_seconds > 0 {
		attempt.last_seen = now
		storage.login_attempts[key] = attempt
		return .Blocked, remaining_seconds
	}
	if is_admin_password_configured(config) && verify_password(config, password, get_admin_password_hash(config)) {
		if ok do remove_login_attempt_locked(storage, key)
		return .Authorized, 0
	}
	attempt.failed_count += 1
	attempt.last_seen = now
	if attempt.failed_count >= MAX_LOGIN_ATTEMPTS {
		attempt.failed_count = 0
		attempt.blocked_until = time.time_add(now, LOGIN_COOLDOWN)
	}
	if ok {
		storage.login_attempts[key] = attempt
	} else {
		stored_key := strings.clone(key, storage.allocator)
		storage.login_attempts[stored_key] = attempt
	}
	if time.diff(now, attempt.blocked_until) > 0 {
		return .Blocked, int(LOGIN_COOLDOWN / time.Second)
	}
	return .Invalid, 0
}

revoke_session :: proc(storage: ^Session_Storage, req: ^http.Request) {
	session_id, exists := get_session_id_from_cookie(req)
	if !exists do return
	sync.lock(&storage.sessions_mu)
	defer sync.unlock(&storage.sessions_mu)
	remove_session_locked(storage, session_id)
}

@(test)
test_session_csrf_validation_accepts_exact_token_only :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	testing.expect(t, arena_err == .None)
	if arena_err != .None do return
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	storage: Session_Storage
	storage_err := session_storage_init(&storage, allocator)
	testing.expect(t, storage_err == .None)
	if storage_err != .None do return
	defer session_storage_destroy(&storage)

	session, session_err := new(Session, allocator)
	testing.expect(t, session_err == .None)
	if session_err != .None do return
	session.id = strings.clone("01234567-89ab-cdef-0123-456789abcdef", allocator)
	session.created_at = time.now()
	session.expires_at = time.time_add(session.created_at, time.Hour)
	for i in 0..<len(session.csrf_secret) {
		session.csrf_secret[i] = byte(i)
	}
	storage.sessions[session.id] = session

	req: http.Request
	http.request_init(&req, allocator)
	http.headers_set_unsafe(
		&req.headers,
		"cookie",
		"session=01234567-89ab-cdef-0123-456789abcdef",
	)

	token_buf: [SESSION_CSRF_TOKEN_BYTES]byte
	defer crypto.zero_explicit(raw_data(token_buf[:]), len(token_buf))
	token, ok := session_csrf_token(&storage, &req, token_buf[:])
	testing.expect(t, ok)
	if !ok do return
	testing.expect(t, validate_session_csrf(&storage, &req, token))
	testing.expect(t, !validate_session_csrf(&storage, &req, token[:len(token) - 1]))

	case_variant := token_buf
	defer crypto.zero_explicit(raw_data(case_variant[:]), len(case_variant))
	testing.expect(t, case_variant[21] == 'a')
	case_variant[21] = 'A'
	testing.expect(t, !validate_session_csrf(&storage, &req, string(case_variant[:])))

	tampered := token_buf
	defer crypto.zero_explicit(raw_data(tampered[:]), len(tampered))
	testing.expect(t, tampered[len(tampered) - 1] == 'f')
	tampered[len(tampered) - 1] = 'e'
	testing.expect(t, !validate_session_csrf(&storage, &req, string(tampered[:])))
}

@(test)
test_revoke_session_removes_storage_record :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	testing.expect(t, arena_err == .None)
	if arena_err != .None do return
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	storage: Session_Storage
	storage_err := session_storage_init(&storage, allocator)
	testing.expect(t, storage_err == .None)
	if storage_err != .None do return
	defer session_storage_destroy(&storage)

	session, session_err := new(Session, allocator)
	testing.expect(t, session_err == .None)
	if session_err != .None do return
	session.id = strings.clone("fedcba98-7654-3210-fedc-ba9876543210", allocator)
	session.created_at = time.now()
	session.expires_at = time.time_add(session.created_at, time.Hour)
	storage.sessions[session.id] = session

	req: http.Request
	http.request_init(&req, allocator)
	http.headers_set_unsafe(
		&req.headers,
		"cookie",
		"session=fedcba98-7654-3210-fedc-ba9876543210",
	)

	revoke_session(&storage, &req)
	_, exists := storage.sessions["fedcba98-7654-3210-fedc-ba9876543210"]
	testing.expect(t, !exists)
}
