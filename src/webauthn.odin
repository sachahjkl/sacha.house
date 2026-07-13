package main

import "core:crypto"
import "core:crypto/ecdsa"
import "core:crypto/hash"
import "core:crypto/sha2"
import "core:encoding/base64"
import "core:encoding/cbor"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:math/rand"
import "core:strings"
import "core:sync"
import "core:time"

import http "lib:odin-http"

WebAuthn_Challenge_Purpose :: enum {
	Registration,
	Authentication,
}

WebAuthn_Challenge :: struct {
	challenge: []byte,
	created_at: time.Time,
	purpose:    WebAuthn_Challenge_Purpose,
}

WebAuthn_Credential :: struct {
	id:         string,
	label:      string,
	public_key: []byte,
	counter:    u32,
}

Stored_Credential :: struct {
	id:         string,
	label:      string,
	public_key: string,
	counter:    u32,
}

Stored_Credentials :: struct {
	version:     int,
	credentials: []Stored_Credential,
}

Legacy_Stored_Credential :: struct {
	id:         string,
	label:      string,
	public_key: string,
	counter:    u32,
}

WebAuthn_Storage :: struct {
	credentials:    map[string]WebAuthn_Credential,
	credentials_mu: sync.Mutex,
	challenges:     map[string]WebAuthn_Challenge,
	challenges_mu:  sync.Mutex,
	config:         ^Config,
	generator:      ^rand.Generator,
	allocator:      mem.Allocator,
}

WebAuthn_Verification_Error :: enum {
	None,
	Invalid_Encoding,
	Invalid_Client_Data,
	Invalid_Type,
	Invalid_Challenge,
	Invalid_Origin,
	Invalid_RP_ID,
	Invalid_Flags,
	Invalid_Credential,
	Unsupported_Algorithm,
	Invalid_Signature,
	Invalid_Counter,
	Storage_Failure,
}

Cose_ES256_Key :: struct {
	sec1: [65]byte,
}

Authenticator_Data :: struct {
	counter:       u32,
	credential_id: []byte,
	cose_key:      []byte,
}

CHALLENGE_EXPIRATION_TIME :: 5 * time.Minute
CHALLENGE_KEY :: "webauthn_challenge"
WEBAUTHN_CREDENTIALS_VERSION :: 2
MAX_WEBAUTHN_CHALLENGES :: 256
MAX_WEBAUTHN_CREDENTIALS :: 64

webauthn_storage_init :: proc(storage: ^WebAuthn_Storage, config: ^Config, generator: ^rand.Generator, allocator: mem.Allocator) -> mem.Allocator_Error {
	storage.config = config
	storage.generator = generator
	storage.allocator = allocator
	storage.credentials = make(map[string]WebAuthn_Credential, allocator)
	storage.challenges = make(map[string]WebAuthn_Challenge, allocator)
	load_webauthn_credentials(storage)
	return .None
}

webauthn_storage_destroy :: proc(storage: ^WebAuthn_Storage) {
	sync.lock(&storage.credentials_mu)
	for _, credential in storage.credentials {
		delete(credential.id, storage.allocator)
		delete(credential.label, storage.allocator)
		delete(credential.public_key, storage.allocator)
	}
	delete(storage.credentials)
	sync.unlock(&storage.credentials_mu)
	sync.lock(&storage.challenges_mu)
	for id, challenge in storage.challenges {
		delete(id, storage.allocator)
		delete(challenge.challenge, storage.allocator)
	}
	delete(storage.challenges)
	sync.unlock(&storage.challenges_mu)
	storage^ = {}
}

webauthn_configured :: proc(config: ^Config) -> bool {
	return strings.trim_space(config.WEBAUTHN_RP_ID) != "" &&
	       strings.trim_space(config.WEBAUTHN_ORIGIN) != ""
}

get_webauthn_rp_id :: proc(config: ^Config) -> string {
	return strings.trim_space(config.WEBAUTHN_RP_ID)
}

get_webauthn_origin :: proc(config: ^Config) -> string {
	return strings.trim_space(config.WEBAUTHN_ORIGIN)
}

get_webauthn_credentials_path :: proc(config: ^Config) -> string {
	return config.WEBAUTHN_CREDENTIALS_FILE
}

load_webauthn_credentials :: proc(storage: ^WebAuthn_Storage) {
	creds_path := get_webauthn_credentials_path(storage.config)
	if creds_path == "" || !os.exists(creds_path) {
		log.info("No WebAuthn credentials file found, starting fresh")
		return
	}
	data, err := os.read_entire_file_from_path(creds_path, context.allocator)
	if err != nil {
		log.warn("Failed to read WebAuthn credentials file")
		return
	}
	defer delete(data)
	stored, needs_migration, ok := parse_stored_credentials(data)
	if !ok do return
	migration_safe := true
	for cred, i in stored.credentials {
		if len(storage.credentials) >= MAX_WEBAUTHN_CREDENTIALS {
			log.warn("Ignoring excess WebAuthn credentials")
			migration_safe = false
			break
		}
		if cred.id == "" || cred.public_key == "" {
			migration_safe = false
			continue
		}
		if _, duplicate := storage.credentials[cred.id]; duplicate {
			migration_safe = false
			continue
		}
		stored_key, decode_ok := decode_base64(cred.public_key)
		if !decode_ok {
			migration_safe = false
			continue
		}
		cose_key, key_err := normalize_stored_cose_key(stored_key)
		if key_err != .None {
			migration_safe = false
			continue
		}
		if crypto.compare_constant_time(stored_key, cose_key) != 1 do needs_migration = true
		label := normalize_passkey_label(cred.label, i + 1)
		if label != cred.label do needs_migration = true
		id_copy := strings.clone(cred.id, storage.allocator)
		label_copy := strings.clone(label, storage.allocator)
		key_copy := make([]byte, len(cose_key), storage.allocator)
		copy(key_copy, cose_key)
		storage.credentials[id_copy] = WebAuthn_Credential {
			id = id_copy,
			label = label_copy,
			public_key = key_copy,
			counter = cred.counter,
		}
	}
	log.infof("Loaded %d WebAuthn credentials", len(storage.credentials))
	if needs_migration && migration_safe && !save_webauthn_credentials_locked(storage) {
		log.error("WebAuthn credential migration could not be persisted")
	}
}

parse_stored_credentials :: proc(data: []byte) -> (Stored_Credentials, bool, bool) {
	stored := Stored_Credentials{}
	needs_migration := false

	if strings.contains(string(data), "\"credentials\"") {
		if err := json.unmarshal(data, &stored, allocator = context.temp_allocator); err != nil {
			log.warnf("Failed to parse WebAuthn credentials: %v", err)
			return stored, false, false
		}
		if stored.version > WEBAUTHN_CREDENTIALS_VERSION {
			log.warn("WebAuthn credentials file uses a newer unsupported version")
			return stored, false, false
		}
		if stored.version != WEBAUTHN_CREDENTIALS_VERSION {
			needs_migration = true
		}
		return stored, needs_migration, true
	}

	legacy := Legacy_Stored_Credential{}
	if err := json.unmarshal(data, &legacy, allocator = context.temp_allocator); err != nil {
		log.warnf("Failed to parse legacy WebAuthn credential: %v", err)
		return stored, false, false
	}
	if legacy.id == "" || legacy.public_key == "" {
		log.warn("Legacy WebAuthn credential file is incomplete")
		return stored, false, false
	}

	stored.version = WEBAUTHN_CREDENTIALS_VERSION
	stored.credentials = make([]Stored_Credential, 1, context.temp_allocator)
	stored.credentials[0] = Stored_Credential {
		id         = legacy.id,
		label      = legacy.label,
		public_key = legacy.public_key,
		counter    = legacy.counter,
	}
	return stored, true, true
}

atomic_write_file :: proc(generator: ^rand.Generator, path: string, data: []byte) -> bool {
	temp_path := fmt.tprintf("%s.tmp.%s", path, generate_id(generator))
	f, open_err := os.open(
		temp_path,
		{.Write, .Create, .Excl, .Trunc, .Sync},
		os.Permissions_Read_All + {.Write_User},
	)
	if open_err != nil {
		log.errorf("Failed to open temporary WebAuthn credentials file: %v", open_err)
		return false
	}

	written, write_err := os.write(f, data)
	if write_err == nil && written != len(data) {
		write_err = .Short_Write
	}
	if write_err == nil {
		write_err = os.sync(f)
	}
	close_err := os.close(f)
	if write_err != nil || close_err != nil {
		_ = os.remove(temp_path)
		log.error("Failed to durably write WebAuthn credentials")
		return false
	}

	if rename_err := os.rename(temp_path, path); rename_err != nil {
		_ = os.remove(temp_path)
		log.errorf("Failed to atomically replace WebAuthn credentials: %v", rename_err)
		return false
	}

	dir_path := os.dir(path)
	dir, dir_err := os.open(dir_path, os.O_RDONLY)
	if dir_err != nil {
		log.error("Failed to open WebAuthn credentials directory for synchronization")
		return false
	}
	dir_sync_err := os.sync(dir)
	dir_close_err := os.close(dir)
	if dir_sync_err != nil || dir_close_err != nil {
		log.error("Failed to synchronize WebAuthn credentials directory")
		return false
	}
	return true
}

save_webauthn_credentials_locked :: proc(storage: ^WebAuthn_Storage) -> bool {
	path := get_webauthn_credentials_path(storage.config)
	if path == "" do return false
	stored := Stored_Credentials{version = WEBAUTHN_CREDENTIALS_VERSION}
	stored.credentials = make([]Stored_Credential, len(storage.credentials), context.temp_allocator)
	i := 0
	for _, cred in storage.credentials {
		stored.credentials[i] = Stored_Credential {
			id = cred.id,
			label = cred.label,
			public_key = base64.encode(cred.public_key, allocator = context.temp_allocator),
			counter = cred.counter,
		}
		i += 1
	}
	data, marshal_err := json.marshal(stored, {pretty = true}, context.temp_allocator)
	if marshal_err != nil do return false
	return atomic_write_file(storage.generator, path, data)
}

normalize_passkey_label :: proc(label: string, fallback_index: int) -> string {
	trimmed := strings.trim_space(label)
	if trimmed != "" do return trimmed
	return fmt.tprintf("Passkey %d", fallback_index)
}

generate_challenge :: proc() -> []byte {
	challenge := make([]byte, 32, context.temp_allocator)
	crypto.rand_bytes(challenge)
	return challenge
}

remove_challenge_locked :: proc(storage: ^WebAuthn_Storage, challenge_id: string) {
	challenge, ok := storage.challenges[challenge_id]
	if !ok do return
	stored_id, _ := delete_key(&storage.challenges, challenge_id)
	delete(stored_id, storage.allocator)
	delete(challenge.challenge, storage.allocator)
}

prune_challenges_locked :: proc(storage: ^WebAuthn_Storage, now: time.Time) {
	expired: [MAX_WEBAUTHN_CHALLENGES]string
	expired_count := 0
	for id, challenge in storage.challenges {
		if time.diff(challenge.created_at, now) > CHALLENGE_EXPIRATION_TIME {
			expired[expired_count] = id
			expired_count += 1
		}
	}
	for id in expired[:expired_count] do remove_challenge_locked(storage, id)
}

store_challenge :: proc(storage: ^WebAuthn_Storage, challenge_id: string, challenge: []byte, purpose: WebAuthn_Challenge_Purpose) -> bool {
	sync.lock(&storage.challenges_mu)
	defer sync.unlock(&storage.challenges_mu)
	prune_challenges_locked(storage, time.now())
	if len(storage.challenges) >= MAX_WEBAUTHN_CHALLENGES do return false
	if _, collision := storage.challenges[challenge_id]; collision do return false
	id_copy := strings.clone(challenge_id, storage.allocator)
	challenge_copy := make([]byte, len(challenge), storage.allocator)
	copy(challenge_copy, challenge)
	storage.challenges[id_copy] = WebAuthn_Challenge {
		challenge = challenge_copy,
		created_at = time.now(),
		purpose = purpose,
	}
	return true
}

discard_challenge :: proc(storage: ^WebAuthn_Storage, challenge_id: string) {
	if len(challenge_id) != 36 do return
	sync.lock(&storage.challenges_mu)
	defer sync.unlock(&storage.challenges_mu)
	remove_challenge_locked(storage, challenge_id)
}

verify_and_consume_challenge :: proc(storage: ^WebAuthn_Storage, challenge_id: string, challenge: []byte, purpose: WebAuthn_Challenge_Purpose) -> bool {
	if len(challenge_id) != 36 || len(challenge) != 32 do return false
	sync.lock(&storage.challenges_mu)
	defer sync.unlock(&storage.challenges_mu)
	now := time.now()
	prune_challenges_locked(storage, now)
	stored, ok := storage.challenges[challenge_id]
	if !ok do return false
	valid := stored.purpose == purpose &&
	         time.diff(stored.created_at, now) <= CHALLENGE_EXPIRATION_TIME &&
	         crypto.compare_constant_time(stored.challenge, challenge) == 1
	remove_challenge_locked(storage, challenge_id)
	return valid
}

store_credential :: proc(storage: ^WebAuthn_Storage, id: string, label: string, public_key: []byte, counter: u32) -> bool {
	sync.lock(&storage.credentials_mu)
	defer sync.unlock(&storage.credentials_mu)
	trimmed_label := strings.trim_space(label)
	if id == "" || len(id) > 2048 || len(trimmed_label) > 128 || len(public_key) == 0 || len(public_key) > 4096 do return false
	if _, exists := storage.credentials[id]; exists || len(storage.credentials) >= MAX_WEBAUTHN_CREDENTIALS do return false
	id_copy := strings.clone(id, storage.allocator)
	label_copy := strings.clone(normalize_passkey_label(label, len(storage.credentials) + 1), storage.allocator)
	key_copy := make([]byte, len(public_key), storage.allocator)
	copy(key_copy, public_key)
	storage.credentials[id_copy] = WebAuthn_Credential {id = id_copy, label = label_copy, public_key = key_copy, counter = counter}
	if !save_webauthn_credentials_locked(storage) {
		delete_key(&storage.credentials, id_copy)
		delete(id_copy, storage.allocator)
		delete(label_copy, storage.allocator)
		delete(key_copy, storage.allocator)
		return false
	}
	return true
}

has_credentials :: proc(storage: ^WebAuthn_Storage) -> bool {
	sync.lock(&storage.credentials_mu)
	defer sync.unlock(&storage.credentials_mu)
	return len(storage.credentials) > 0
}

list_credentials :: proc(storage: ^WebAuthn_Storage, allocator := context.temp_allocator) -> []WebAuthn_Credential {
	sync.lock(&storage.credentials_mu)
	defer sync.unlock(&storage.credentials_mu)
	credentials := make([dynamic]WebAuthn_Credential, 0, len(storage.credentials), allocator)
	for _, cred in storage.credentials {
		key_copy := make([]byte, len(cred.public_key), allocator)
		copy(key_copy, cred.public_key)
		append(&credentials, WebAuthn_Credential {id = strings.clone(cred.id, allocator), label = strings.clone(cred.label, allocator), public_key = key_copy, counter = cred.counter})
	}
	return credentials[:]
}

remove_credential :: proc(storage: ^WebAuthn_Storage, id: string) -> bool {
	sync.lock(&storage.credentials_mu)
	defer sync.unlock(&storage.credentials_mu)
	credential, ok := storage.credentials[id]
	if !ok do return false
	delete_key(&storage.credentials, id)
	if !save_webauthn_credentials_locked(storage) {
		storage.credentials[credential.id] = credential
		return false
	}
	delete(credential.id, storage.allocator)
	delete(credential.label, storage.allocator)
	delete(credential.public_key, storage.allocator)
	return true
}

decode_base64 :: proc(value: string) -> ([]byte, bool) {
	if value == "" || len(value) > 128 * 1024 || len(value) % 4 == 1 {
		return nil, false
	}
	normalized, _ := strings.replace_all(value, "-", "+", context.temp_allocator)
	normalized, _ = strings.replace_all(normalized, "_", "/", context.temp_allocator)
	switch len(normalized) % 4 {
	case 2:
		normalized = fmt.aprintf("%s==", normalized, allocator = context.temp_allocator)
	case 3:
		normalized = fmt.aprintf("%s=", normalized, allocator = context.temp_allocator)
	}
	decoded, err := base64.decode(normalized, allocator = context.temp_allocator)
	return decoded, err == nil
}

verify_credential_binding :: proc(id, raw_id: string) -> bool {
	id_bytes, id_ok := decode_base64(id)
	raw_bytes, raw_ok := decode_base64(raw_id)
	return id_ok && raw_ok && crypto.compare_constant_time(id_bytes, raw_bytes) == 1
}

verify_user_handle :: proc(user_handle_b64: string) -> bool {
	if user_handle_b64 == "" {
		return true
	}
	handle, ok := decode_base64(user_handle_b64)
	expected_handle := [5]byte{'a', 'd', 'm', 'i', 'n'}
	return ok && crypto.compare_constant_time(handle, expected_handle[:]) == 1
}

verify_client_data_json :: proc(
	config: ^Config,
	client_data_b64: string,
	expected_type: string,
) -> (challenge: []byte, err: WebAuthn_Verification_Error) {
	client_data_bytes, decode_ok := decode_base64(client_data_b64)
	if !decode_ok {
		return nil, .Invalid_Encoding
	}

	client_data: map[string]json.Value
	if json_err := json.unmarshal(client_data_bytes, &client_data, allocator = context.temp_allocator); json_err != nil {
		return nil, .Invalid_Client_Data
	}

	type_value, has_type := client_data["type"]
	type_string, type_ok := type_value.(string)
	if !has_type || !type_ok || type_string != expected_type {
		return nil, .Invalid_Type
	}

	origin_value, has_origin := client_data["origin"]
	origin, origin_ok := origin_value.(string)
	if !has_origin || !origin_ok || origin != get_webauthn_origin(config) {
		return nil, .Invalid_Origin
	}

	if cross_origin_value, present := client_data["crossOrigin"]; present {
		cross_origin, bool_ok := cross_origin_value.(bool)
		if !bool_ok || cross_origin {
			return nil, .Invalid_Origin
		}
	}

	challenge_value, has_challenge := client_data["challenge"]
	challenge_string, challenge_ok := challenge_value.(string)
	if !has_challenge || !challenge_ok {
		return nil, .Invalid_Challenge
	}
	challenge, decode_ok = decode_base64(challenge_string)
	if !decode_ok || len(challenge) != 32 {
		return nil, .Invalid_Challenge
	}
	return challenge, .None
}

cbor_integer :: proc(value: cbor.Value) -> (i64, bool) {
	switch v in value {
	case u8:  return i64(v), true
	case u16: return i64(v), true
	case u32: return i64(v), true
	case u64:
		if v > u64(max(i64)) { return 0, false }
		return i64(v), true
	case cbor.Negative_U8:  return i64(cbor.negative_to_int(v)), true
	case cbor.Negative_U16: return i64(cbor.negative_to_int(v)), true
	case cbor.Negative_U32: return i64(cbor.negative_to_int(v)), true
	case cbor.Negative_U64:
		return 0, false
	case nil:
		return 0, false
	case ^cbor.Bytes:
		return 0, false
	case ^cbor.Text:
		return 0, false
	case ^cbor.Array:
		return 0, false
	case ^cbor.Map:
		return 0, false
	case ^cbor.Tag:
		return 0, false
	case cbor.Simple:
		return 0, false
	case f16:
		return 0, false
	case f32:
		return 0, false
	case f64:
		return 0, false
	case bool:
		return 0, false
	case cbor.Undefined:
		return 0, false
	case cbor.Nil:
		return 0, false
	}
	return 0, false
}

cbor_map_get_integer :: proc(entries: ^cbor.Map, key: i64) -> (cbor.Value, bool) {
	for entry in entries^ {
		entry_key, ok := cbor_integer(entry.key)
		if ok && entry_key == key {
			return entry.value, true
		}
	}
	return nil, false
}

cbor_map_get_text :: proc(entries: ^cbor.Map, key: string) -> (cbor.Value, bool) {
	for entry in entries^ {
		entry_key, ok := entry.key.(^cbor.Text)
		if ok && entry_key != nil && entry_key^ == key {
			return entry.value, true
		}
	}
	return nil, false
}

parse_cose_es256_key :: proc(cose_key: []byte) -> (Cose_ES256_Key, WebAuthn_Verification_Error) {
	result := Cose_ES256_Key{}
	decoded, decode_err := cbor.decode(string(cose_key), cbor.Decoder_Flags{.Disallow_Streaming}, context.temp_allocator)
	if decode_err != nil {
		return result, .Invalid_Credential
	}
	defer cbor.destroy(decoded, context.temp_allocator)
	entries, map_ok := decoded.(^cbor.Map)
	if !map_ok || entries == nil {
		return result, .Invalid_Credential
	}

	alg_value, has_alg := cbor_map_get_integer(entries, 3)
	alg, alg_ok := cbor_integer(alg_value)
	if !has_alg || !alg_ok {
		return result, .Invalid_Credential
	}
	if alg != -7 {
		return result, .Unsupported_Algorithm
	}

	kty_value, has_kty := cbor_map_get_integer(entries, 1)
	crv_value, has_crv := cbor_map_get_integer(entries, -1)
	kty, kty_ok := cbor_integer(kty_value)
	crv, crv_ok := cbor_integer(crv_value)
	if !has_kty || !has_crv || !kty_ok || !crv_ok || kty != 2 || crv != 1 {
		return result, .Unsupported_Algorithm
	}

	x_value, has_x := cbor_map_get_integer(entries, -2)
	y_value, has_y := cbor_map_get_integer(entries, -3)
	x, x_ok := x_value.(^cbor.Bytes)
	y, y_ok := y_value.(^cbor.Bytes)
	if !has_x || !has_y || !x_ok || !y_ok || x == nil || y == nil || len(x^) != 32 || len(y^) != 32 {
		return result, .Invalid_Credential
	}

	result.sec1[0] = 0x04
	copy(result.sec1[1:33], x^)
	copy(result.sec1[33:65], y^)
	return result, .None
}

canonicalize_cose_map :: proc(cose_key: []byte) -> ([]byte, bool) {
	decoded, decode_err := cbor.decode(string(cose_key), cbor.Decoder_Flags{.Disallow_Streaming}, context.temp_allocator)
	if decode_err != nil {
		return nil, false
	}
	defer cbor.destroy(decoded, context.temp_allocator)
	entries, map_ok := decoded.(^cbor.Map)
	if !map_ok || entries == nil {
		return nil, false
	}
	if _, has_alg := cbor_map_get_integer(entries, 3); !has_alg {
		return nil, false
	}
	encoded, encode_err := cbor.encode(decoded, cbor.ENCODE_FULLY_DETERMINISTIC, context.temp_allocator)
	return encoded, encode_err == nil
}

canonicalize_cose_key :: proc(cose_key: []byte) -> ([]byte, WebAuthn_Verification_Error) {
	_, key_err := parse_cose_es256_key(cose_key)
	if key_err != .None {
		return nil, key_err
	}
	decoded, decode_err := cbor.decode(string(cose_key), cbor.Decoder_Flags{.Disallow_Streaming}, context.temp_allocator)
	if decode_err != nil {
		return nil, .Invalid_Credential
	}
	defer cbor.destroy(decoded, context.temp_allocator)
	encoded, encode_err := cbor.encode(decoded, cbor.ENCODE_FULLY_DETERMINISTIC, context.temp_allocator)
	if encode_err != nil {
		return nil, .Invalid_Credential
	}
	return encoded, .None
}

extract_attestation_auth_data :: proc(attestation: []byte) -> ([]byte, bool) {
	decoded, decode_err := cbor.decode(string(attestation), cbor.Decoder_Flags{.Disallow_Streaming}, context.temp_allocator)
	if decode_err != nil {
		return nil, false
	}
	defer cbor.destroy(decoded, context.temp_allocator)
	entries, map_ok := decoded.(^cbor.Map)
	if !map_ok || entries == nil {
		return nil, false
	}
	auth_value, present := cbor_map_get_text(entries, "authData")
	auth_data, bytes_ok := auth_value.(^cbor.Bytes)
	if !present || !bytes_ok || auth_data == nil {
		return nil, false
	}
	result := make([]byte, len(auth_data^), context.temp_allocator)
	copy(result, auth_data^)
	return result, true
}

normalize_stored_cose_key :: proc(stored_key: []byte) -> ([]byte, WebAuthn_Verification_Error) {
	if canonical, ok := canonicalize_cose_map(stored_key); ok {
		return canonical, .None
	}

	auth_data, ok := extract_attestation_auth_data(stored_key)
	if !ok || len(auth_data) < 55 || auth_data[32] & 0x40 == 0 {
		return nil, .Invalid_Credential
	}
	credential_id_len := int(auth_data[53]) << 8 | int(auth_data[54])
	cose_offset := 55 + credential_id_len
	if credential_id_len == 0 || cose_offset >= len(auth_data) {
		return nil, .Invalid_Credential
	}
	canonical, canonical_ok := canonicalize_cose_map(auth_data[cose_offset:])
	if !canonical_ok {
		return nil, .Invalid_Credential
	}
	return canonical, .None
}

sha256_bytes :: proc(data: []byte) -> (digest: [32]byte) {
	hasher: sha2.Context_256
	sha2.init_256(&hasher)
	sha2.update(&hasher, data)
	sha2.final(&hasher, digest[:])
	return
}

read_u32_be :: proc(data: []byte) -> u32 {
	return u32(data[0]) << 24 | u32(data[1]) << 16 | u32(data[2]) << 8 | u32(data[3])
}

parse_authenticator_data :: proc(
	config: ^Config,
	auth_data: []byte,
	expect_attested_credential: bool,
) -> (Authenticator_Data, WebAuthn_Verification_Error) {
	result := Authenticator_Data{}
	if len(auth_data) < 37 {
		return result, .Invalid_Credential
	}

	rp_hash := sha256_bytes(transmute([]byte)get_webauthn_rp_id(config))
	if crypto.compare_constant_time(auth_data[:32], rp_hash[:]) != 1 {
		return result, .Invalid_RP_ID
	}

	flags := auth_data[32]
	if flags & 0x01 == 0 || (config.WEBAUTHN_REQUIRE_USER_VERIFICATION && flags & 0x04 == 0) {
		return result, .Invalid_Flags
	}
	if flags & 0x10 != 0 && flags & 0x08 == 0 {
		return result, .Invalid_Flags
	}
	result.counter = read_u32_be(auth_data[33:37])

	if !expect_attested_credential {
		if flags & 0x40 != 0 {
			return result, .Invalid_Flags
		}
		return result, .None
	}
	if flags & 0x40 == 0 || len(auth_data) < 55 {
		return result, .Invalid_Flags
	}

	credential_id_len := int(auth_data[53]) << 8 | int(auth_data[54])
	credential_end := 55 + credential_id_len
	if credential_id_len == 0 || credential_end >= len(auth_data) {
		return result, .Invalid_Credential
	}
	result.credential_id = auth_data[55:credential_end]
	result.cose_key = auth_data[credential_end:]
	return result, .None
}

verify_attestation_object :: proc(
	config: ^Config,
	attestation_object_b64: string,
	expected_raw_id_b64: string,
) -> (public_key: []byte, counter: u32, err: WebAuthn_Verification_Error) {
	attestation, decode_ok := decode_base64(attestation_object_b64)
	if !decode_ok {
		return nil, 0, .Invalid_Encoding
	}
	auth_data, auth_ok := extract_attestation_auth_data(attestation)
	if !auth_ok {
		return nil, 0, .Invalid_Credential
	}
	parsed, parse_err := parse_authenticator_data(config, auth_data, true)
	if parse_err != .None {
		return nil, 0, parse_err
	}
	raw_id, raw_ok := decode_base64(expected_raw_id_b64)
	if !raw_ok || crypto.compare_constant_time(parsed.credential_id, raw_id) != 1 {
		return nil, 0, .Invalid_Credential
	}
	canonical_key, key_err := canonicalize_cose_key(parsed.cose_key)
	if key_err != .None {
		return nil, 0, key_err
	}
	return canonical_key, parsed.counter, .None
}

verify_assertion_signature :: proc(
	storage: ^WebAuthn_Storage,
	config: ^Config,
	credential_id: string,
	authenticator_data_b64: string,
	client_data_json_b64: string,
	signature_b64: string,
) -> WebAuthn_Verification_Error {
	auth_data, auth_ok := decode_base64(authenticator_data_b64)
	client_data, client_ok := decode_base64(client_data_json_b64)
	signature, signature_ok := decode_base64(signature_b64)
	if !auth_ok || !client_ok || !signature_ok || len(signature) == 0 {
		return .Invalid_Encoding
	}
	parsed_auth, auth_err := parse_authenticator_data(config, auth_data, false)
	if auth_err != .None {
		return auth_err
	}

	sync.lock(&storage.credentials_mu)
	defer sync.unlock(&storage.credentials_mu)
	credential, exists := storage.credentials[credential_id]
	if !exists {
		return .Invalid_Credential
	}

	cose_key, key_err := parse_cose_es256_key(credential.public_key)
	if key_err != .None {
		return key_err
	}
	public_key: ecdsa.Public_Key
	if !ecdsa.public_key_set_bytes(&public_key, .SECP256R1, cose_key.sec1[:]) {
		return .Invalid_Credential
	}
	defer ecdsa.public_key_clear(&public_key)

	client_hash := sha256_bytes(client_data)
	signed_data := make([]byte, len(auth_data) + len(client_hash), context.temp_allocator)
	copy(signed_data, auth_data)
	copy(signed_data[len(auth_data):], client_hash[:])
	if !ecdsa.verify_asn1(&public_key, hash.Algorithm.SHA256, signed_data, signature) {
		return .Invalid_Signature
	}

	old_counter := credential.counter
	new_counter := parsed_auth.counter
	if old_counter != 0 && new_counter <= old_counter {
		return .Invalid_Counter
	}
	if old_counter == 0 && new_counter == 0 {
		return .None
	}
	credential.counter = new_counter
	storage.credentials[credential.id] = credential
	if !save_webauthn_credentials_locked(storage) {
		credential.counter = old_counter
		storage.credentials[credential.id] = credential
		return .Storage_Failure
	}
	return .None
}

set_challenge_cookie :: proc(config: ^Config, req: ^http.Request, res: ^http.Response, challenge_id: string) {
	append(
		&res.cookies,
		http.Cookie {
			name = CHALLENGE_KEY,
			value = challenge_id,
			path = "/admin/webauthn",
			http_only = true,
			secure = auth_cookie_secure(config, req),
			same_site = .Strict,
			max_age_secs = int(CHALLENGE_EXPIRATION_TIME / time.Second),
		},
	)
}

clear_challenge_cookie :: proc(config: ^Config, req: ^http.Request, res: ^http.Response) {
	append(
		&res.cookies,
		http.Cookie {
			name = CHALLENGE_KEY,
			value = "",
			path = "/admin/webauthn",
			http_only = true,
			secure = auth_cookie_secure(config, req),
			same_site = .Strict,
			max_age_secs = 0,
		},
	)
}
