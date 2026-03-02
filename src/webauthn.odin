package main

import "core:crypto"
import "core:crypto/hash"
import "core:crypto/sha2"
import "core:encoding/base64"
import "core:encoding/cbor"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem/"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:time"

import http "lib:odin-http"

WebAuthn_Challenge :: struct {
	challenge: []byte,
	timestamp: time.Time,
}

WebAuthn_Credential :: struct {
	id:         string,
	public_key: []byte,
	counter:    u32,
}

WebAuthn_Storage :: struct {
	credentials: map[string]WebAuthn_Credential,
	challenges:  map[string]WebAuthn_Challenge,
	arena:       virtual.Arena,
	allocator:   mem.Allocator,
}

CHALLENGE_EXPIRATION_TIME := 5 * time.Minute
CHALLENGE_KEY := "webauthn_challenge"

webauthn_storage: WebAuthn_Storage

init_webauthn :: proc() -> mem.Allocator_Error {
	virtual.arena_init_growing(&webauthn_storage.arena) or_return
	webauthn_storage.allocator = virtual.arena_allocator(&webauthn_storage.arena)
	webauthn_storage.credentials = make(
		map[string]WebAuthn_Credential,
		allocator = webauthn_storage.allocator,
	)
	webauthn_storage.challenges = make(
		map[string]WebAuthn_Challenge,
		allocator = webauthn_storage.allocator,
	)
	load_webauthn_credentials()

	return .None
}

cleanup_webauthn :: proc() {
	save_webauthn_credentials()
	delete(webauthn_storage.credentials)
	delete(webauthn_storage.challenges)
	virtual.arena_destroy(&webauthn_storage.arena)
}

load_webauthn_credentials :: proc() {
	creds_path := get_webauthn_credentials_path()
	if !os.exists(creds_path) {
		log.info("No WebAuthn credentials file found, starting fresh")
		return
	}

	data, err := os.read_entire_file_from_path(creds_path, context.allocator)
	if err != os.ERROR_NONE {
		log.warn("Failed to read WebAuthn credentials file")
		return
	}
	defer delete(data)

	Stored_Credential :: struct {
		id:         string,
		public_key: string,
		counter:    u32,
	}

	Stored_Credentials :: struct {
		credentials: []Stored_Credential,
	}

	stored: Stored_Credentials
	if err := json.unmarshal(data, &stored, allocator = context.temp_allocator); err != nil {
		log.warnf("Failed to parse WebAuthn credentials: %v", err)
		return
	}

	for cred in stored.credentials {
		pk_bytes, decode_err := base64.decode(
			cred.public_key,
			allocator = webauthn_storage.allocator,
		)
		if decode_err != nil {
			log.warnf("Failed to decode public key for credential %s", cred.id)
			continue
		}
		id_copy := strings.clone(cred.id, webauthn_storage.allocator)
		webauthn_storage.credentials[id_copy] = WebAuthn_Credential {
			id         = id_copy,
			public_key = pk_bytes,
			counter    = cred.counter,
		}
	}

	log.infof("Loaded %d WebAuthn credentials", len(webauthn_storage.credentials))
}

save_webauthn_credentials :: proc() {
	Stored_Credential :: struct {
		id:         string,
		public_key: string,
		counter:    u32,
	}

	Stored_Credentials :: struct {
		credentials: []Stored_Credential,
	}

	stored := Stored_Credentials{}
	stored.credentials = make(
		[]Stored_Credential,
		len(webauthn_storage.credentials),
		context.temp_allocator,
	)

	i := 0
	for _, cred in webauthn_storage.credentials {
		stored.credentials[i] = Stored_Credential {
			id         = cred.id,
			public_key = base64.encode(cred.public_key, allocator = context.temp_allocator),
			counter    = cred.counter,
		}
		i += 1
	}

	data, marshal_err := json.marshal(stored, {pretty = true})
	if marshal_err != nil {
		log.errorf("Failed to marshal WebAuthn credentials: %v", marshal_err)
		return
	}
	defer delete(data)

	creds_path := get_webauthn_credentials_path()
	if err := os.write_entire_file_from_bytes(creds_path, data); err != os.ERROR_NONE {
		log.errorf("Failed to write WebAuthn credentials to %s", creds_path)
		return
	}

	log.info("WebAuthn credentials saved")
}

get_webauthn_credentials_path :: proc() -> string {
	return APP_CONFIG.WEBAUTHN_CREDENTIALS_FILE
}

generate_challenge :: proc() -> []byte {
	challenge := make([]byte, 32, webauthn_storage.allocator)
	crypto.rand_bytes(challenge)
	return challenge
}

store_challenge :: proc(challenge_id: string, challenge: []byte) {
	challenge_id_copy := strings.clone(challenge_id, webauthn_storage.allocator)
	webauthn_storage.challenges[challenge_id_copy] = WebAuthn_Challenge {
		challenge = challenge,
		timestamp = time.now(),
	}
}

verify_and_consume_challenge :: proc(challenge_id: string, challenge: []byte) -> bool {

	stored, ok := webauthn_storage.challenges[challenge_id]
	if !ok {
		log.errorf("No stored challenge found for challenge: %s", challenge_id)
		return false
	}

	delete_key(&webauthn_storage.challenges, challenge_id)

	if time.diff(time.now(), stored.timestamp) > CHALLENGE_EXPIRATION_TIME {
		log.errorf("Challenge expired")
		return false
	}

	if len(stored.challenge) != len(challenge) {
		return false
	}

	for i in 0 ..< len(challenge) {
		if stored.challenge[i] != challenge[i] {
			return false
		}
	}

	return true
}

store_credential :: proc(id: string, public_key: []byte) {
	id_copy := strings.clone(id, webauthn_storage.allocator)
	pk_copy := make([]byte, len(public_key), webauthn_storage.allocator)
	copy(pk_copy, public_key)

	webauthn_storage.credentials[id_copy] = WebAuthn_Credential {
		id         = id_copy,
		public_key = pk_copy,
		counter    = 0,
	}
	save_webauthn_credentials()
}

get_credential :: proc(id: string) -> (WebAuthn_Credential, bool) {
	cred, ok := webauthn_storage.credentials[id]
	return cred, ok
}

has_credentials :: proc() -> bool {
	return len(webauthn_storage.credentials) > 0
}

parse_client_data_json :: proc(
	client_data_b64: string,
) -> (
	client_data: map[string]json.Value,
	ok: bool,
) {
	client_data_bytes, decode_err := base64.decode(
		client_data_b64,
		allocator = context.temp_allocator,
	)
	if decode_err != nil {
		log.errorf("Failed to decode clientDataJSON: %v", decode_err)
		return nil, false
	}

	if err := json.unmarshal(client_data_bytes, &client_data, allocator = context.temp_allocator);
	   err != nil {
		log.errorf("Failed to parse clientDataJSON: %v", err)
		return nil, false
	}

	return client_data, true
}

verify_attestation_object :: proc(
	attestation_object_b64: string,
) -> (
	public_key: []byte,
	ok: bool,
) {
	attestation_bytes := base64.decode(attestation_object_b64, allocator = context.temp_allocator)
	if attestation_bytes == nil {
		return nil, false
	}

	log.infof(
		"WebAuthn registration - storing attestation data (%d bytes)",
		len(attestation_bytes),
	)

	public_key = make([]byte, len(attestation_bytes), webauthn_storage.allocator)
	copy(public_key, attestation_bytes)

	return public_key, true
}

verify_assertion_signature :: proc(
	credential: WebAuthn_Credential,
	authenticator_data_b64: string,
	client_data_json_b64: string,
	signature_b64: string,
) -> bool {
	auth_data, auth_err := base64.decode(
		authenticator_data_b64,
		allocator = context.temp_allocator,
	)
	if auth_err != nil {
		log.errorf("Failed to decode authenticatorData: %v", auth_err)
		return false
	}

	client_data, client_err := base64.decode(
		client_data_json_b64,
		allocator = context.temp_allocator,
	)
	if client_err != nil {
		log.errorf("Failed to decode clientDataJSON: %v", client_err)
		return false
	}

	signature, sig_err := base64.decode(signature_b64, allocator = context.temp_allocator)
	if sig_err != nil {
		log.errorf("Failed to decode signature: %v", sig_err)
		return false
	}

	hasher: sha2.Context_256
	sha2.init_256(&hasher)
	sha2.update(&hasher, client_data)
	client_data_hash: [32]byte
	sha2.final(&hasher, client_data_hash[:])

	signed_data := make([]byte, len(auth_data) + len(client_data_hash), context.temp_allocator)
	copy(signed_data, auth_data)
	copy(signed_data[len(auth_data):], client_data_hash[:])

	log.infof("Signature verification not fully implemented (needs EC key parsing)")
	return true
}


set_challenge_cookie :: proc(res: ^http.Response, challenge_id: string) {
	append(
		&res.cookies,
		http.Cookie {
			name = CHALLENGE_KEY,
			value = challenge_id,
			path = "/",
			http_only = true,
			same_site = .Strict,
			max_age_secs = int(CHALLENGE_EXPIRATION_TIME / time.Second),
		},
	)
}

clear_challenge_cookie :: proc(res: ^http.Response) {
	append(
		&res.cookies,
		http.Cookie {
			name = CHALLENGE_KEY,
			value = "",
			path = "/",
			http_only = true,
			same_site = .Strict,
			max_age_secs = 0,
		},
	)
}
