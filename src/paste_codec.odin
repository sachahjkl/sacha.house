package main

import "core:crypto"
import "core:crypto/aead"
import endian "core:encoding/endian"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import "core:testing"

PASTE_V1_VERSION              :: 1
PASTE_V1_ALGORITHM_ID         :: byte(1)
PASTE_V1_ALGORITHM_NAME       :: "xchacha20poly1305"
PASTE_KEY_BYTES               :: 32
PASTE_PID_BYTES               :: 16
PASTE_NONCE_BYTES             :: 24
PASTE_TAG_BYTES               :: 16
PASTE_TITLE_MAX_BYTES         :: 200
PASTE_KEY_ID_MAX_BYTES        :: 63
PASTE_KEYRING_MAX_KEYS        :: 16
PASTE_PLAINTEXT_HEADER_BYTES  :: 28
PASTE_AAD_PURPOSE             :: "sacha.house/paste"
PASTE_AAD_MAX_BYTES           :: len(PASTE_AAD_PURPOSE) + 1 + 1 + 1 + 1 + PASTE_KEY_ID_MAX_BYTES + PASTE_PID_BYTES
PASTE_PLAINTEXT_MAGIC         :: [4]byte{'S', 'H', 'P', '1'}

PASTE_ENVELOPE_PREFIX         :: `{"v":1,"alg":"xchacha20poly1305","kid":"`
PASTE_ENVELOPE_PID_SEPARATOR  :: `","pid":"`
PASTE_ENVELOPE_NONCE_SEPARATOR :: `","nonce":"`
PASTE_ENVELOPE_CIPHER_SEPARATOR :: `","ciphertext":"`
PASTE_ENVELOPE_TAG_SEPARATOR  :: `","tag":"`
PASTE_ENVELOPE_SUFFIX         :: `"}`

Paste_Key_Config :: struct {
	id:      string,
	key_hex: string,
}

Paste_Secrets_Config :: struct {
	github_gist_token: string,
	active_key_id:     string,
	keys:              []Paste_Key_Config,
}

Paste_Secrets_Error :: enum {
	None,
	Invalid_JSON,
	Invalid_Shape,
	Empty_Token,
	Invalid_Key_Count,
	Invalid_Key_Id,
	Duplicate_Key_Id,
	Duplicate_Key_Material,
	Invalid_Key_Material,
	Missing_Active_Key,
	Allocation,
}

Paste_Key :: struct {
	id:       string,
	material: [PASTE_KEY_BYTES]byte,
}

Paste_Keyring :: struct {
	active: ^Paste_Key,
	by_id:  map[string]^Paste_Key,
	owned:  [dynamic]^Paste_Key,
}

Paste_Codec :: struct {
	keys: ^Paste_Keyring,
}

Paste_Document :: struct {
	title:      string,
	body:       string,
	created_ms: i64,
	updated_ms: i64,
	storage:    []byte,
}

Paste_Envelope_V1 :: struct {
	v:          int,
	alg:        string,
	kid:        string,
	pid:        string,
	nonce:      string,
	ciphertext: string,
	tag:        string,
}

Paste_Codec_Error :: enum {
	None,
	Invalid_Input,
	Too_Large,
	Invalid_Envelope,
	Unsupported_Version,
	Unsupported_Algorithm,
	Key_Unavailable,
	Authentication_Failed,
	Allocation,
}

paste_key_id_is_valid :: proc(id: string) -> bool {
	if len(id) < 1 || len(id) > PASTE_KEY_ID_MAX_BYTES {
		return false
	}
	for c in id {
		if !('A' <= c && c <= 'Z') && !('a' <= c && c <= 'z') &&
		   !('0' <= c && c <= '9') && c != '.' && c != '_' && c != '-' {
			return false
		}
	}
	return true
}

paste_lower_hex_is_valid :: proc(value: string, exact_length: int) -> bool {
	if len(value) != exact_length {
		return false
	}
	for c in value {
		if !('0' <= c && c <= '9') && !('a' <= c && c <= 'f') {
			return false
		}
	}
	return true
}

paste_secret_token_is_valid :: proc(token: string) -> bool {
	if len(token) == 0 || !utf8.valid_string(token) {
		return false
	}
	for c in token {
		if c == 0 || c == '\r' || c == '\n' {
			return false
		}
	}
	return true
}

paste_secrets_validate :: proc(secrets: ^Paste_Secrets_Config) -> Paste_Secrets_Error {
	if secrets == nil || !paste_secret_token_is_valid(secrets.github_gist_token) {
		return .Empty_Token
	}
	if len(secrets.keys) < 1 || len(secrets.keys) > PASTE_KEYRING_MAX_KEYS {
		return .Invalid_Key_Count
	}
	if !paste_key_id_is_valid(secrets.active_key_id) {
		return .Missing_Active_Key
	}

	active_found := false
	for key, i in secrets.keys {
		if !paste_key_id_is_valid(key.id) {
			return .Invalid_Key_Id
		}
		if !paste_lower_hex_is_valid(key.key_hex, PASTE_KEY_BYTES * 2) {
			return .Invalid_Key_Material
		}
		if key.id == secrets.active_key_id {
			active_found = true
		}
		for j in 0..<i {
			if key.id == secrets.keys[j].id {
				return .Duplicate_Key_Id
			}
			if crypto.compare_constant_time(
				transmute([]byte)key.key_hex,
				transmute([]byte)secrets.keys[j].key_hex,
			) == 1 {
				return .Duplicate_Key_Material
			}
		}
	}
	if !active_found {
		return .Missing_Active_Key
	}
	return .None
}

paste_wipe_bytes :: proc(data: []byte) {
	if len(data) != 0 {
		crypto.zero_explicit(raw_data(data), len(data))
	}
}

paste_wipe_string :: proc(value: string) {
	if len(value) != 0 {
		bytes := transmute([]byte)value
		crypto.zero_explicit(raw_data(bytes), len(bytes))
	}
}

// This destroys a secrets DTO produced by the JSON loader. Call it only for
// strings and slices owned by allocator, after the token and keys are copied
// into their final owners.
paste_secrets_destroy :: proc(secrets: ^Paste_Secrets_Config, allocator: mem.Allocator) {
	if secrets == nil {
		return
	}
	paste_wipe_string(secrets.github_gist_token)
	delete(secrets.github_gist_token, allocator)
	delete(secrets.active_key_id, allocator)
	for &key in secrets.keys {
		delete(key.id, allocator)
		paste_wipe_string(key.key_hex)
		delete(key.key_hex, allocator)
	}
	delete(secrets.keys, allocator)
	secrets^ = {}
}

paste_hex_nibble :: proc(c: byte) -> (byte, bool) {
	if '0' <= c && c <= '9' {
		return c - '0', true
	}
	if 'a' <= c && c <= 'f' {
		return c - 'a' + 10, true
	}
	return 0, false
}

paste_decode_lower_hex :: proc(value: string, allocator: mem.Allocator) -> ([]byte, Paste_Codec_Error) {
	if len(value) % 2 != 0 {
		return nil, .Invalid_Envelope
	}
	decoded, alloc_err := make([]byte, len(value) / 2, allocator)
	if alloc_err != nil {
		return nil, .Allocation
	}
	for i in 0..<len(decoded) {
		hi, hi_ok := paste_hex_nibble(value[i * 2])
		lo, lo_ok := paste_hex_nibble(value[i * 2 + 1])
		if !hi_ok || !lo_ok {
			paste_wipe_bytes(decoded)
			delete(decoded, allocator)
			return nil, .Invalid_Envelope
		}
		decoded[i] = hi << 4 | lo
	}
	return decoded, .None
}

paste_keyring_init :: proc(
	keyring: ^Paste_Keyring,
	secrets: ^Paste_Secrets_Config,
	allocator: mem.Allocator,
) -> (err: Paste_Secrets_Error) {
	if keyring == nil {
		return .Allocation
	}
	keyring^ = {}
	if validation_err := paste_secrets_validate(secrets); validation_err != .None {
		return validation_err
	}

	keyring.by_id = make(map[string]^Paste_Key, allocator)
	defer if err != .None {
		paste_keyring_destroy(keyring, allocator)
	}

	owned, owned_err := make([dynamic]^Paste_Key, 0, len(secrets.keys), allocator)
	if owned_err != nil {
		return .Allocation
	}
	keyring.owned = owned

	for key_config in secrets.keys {
		decoded, decode_err := paste_decode_lower_hex(key_config.key_hex, allocator)
		if decode_err != .None || len(decoded) != PASTE_KEY_BYTES {
			if decoded != nil {
				paste_wipe_bytes(decoded)
				delete(decoded, allocator)
			}
			return .Allocation if decode_err == .Allocation else .Invalid_Key_Material
		}

		key, key_alloc_err := new(Paste_Key, allocator)
		if key_alloc_err != nil {
			paste_wipe_bytes(decoded)
			delete(decoded, allocator)
			return .Allocation
		}
		key^ = {}
		id_copy, id_alloc_err := strings.clone(key_config.id, allocator)
		if id_alloc_err != nil {
			paste_wipe_bytes(decoded)
			delete(decoded, allocator)
			free(key, allocator)
			return .Allocation
		}
		key.id = id_copy
		copy(key.material[:], decoded)
		paste_wipe_bytes(decoded)
		delete(decoded, allocator)

		append(&keyring.owned, key)
		keyring.by_id[key.id] = key
	}

	active, found := keyring.by_id[secrets.active_key_id]
	if !found {
		return .Missing_Active_Key
	}
	keyring.active = active
	return .None
}

paste_keyring_destroy :: proc(keyring: ^Paste_Keyring, allocator: mem.Allocator) {
	if keyring == nil {
		return
	}
	if keyring.by_id != nil {
		delete(keyring.by_id)
	}
	for key in keyring.owned {
		if key == nil {
			continue
		}
		delete(key.id, allocator)
		crypto.zero_explicit(raw_data(key.material[:]), len(key.material))
		free(key, allocator)
	}
	if keyring.owned != nil {
		delete(keyring.owned)
	}
	keyring^ = {}
}

paste_codec_init :: proc(codec: ^Paste_Codec, keyring: ^Paste_Keyring) -> Paste_Codec_Error {
	if codec == nil || keyring == nil || keyring.active == nil || keyring.by_id == nil {
		return .Invalid_Input
	}
	codec.keys = keyring
	return .None
}

paste_codec_destroy :: proc(codec: ^Paste_Codec) {
	if codec != nil {
		codec^ = {}
	}
}

paste_max_body_is_valid :: proc(max_body_bytes: int) -> bool {
	if max_body_bytes < 0 || u64(max_body_bytes) > u64(max(u32)) {
		return false
	}
	max_clear := u64(PASTE_PLAINTEXT_HEADER_BYTES + PASTE_TITLE_MAX_BYTES) + u64(max_body_bytes)
	return max_clear <= u64(max(int)) / 2
}

paste_document_fields_are_valid :: proc(
	title, body: string,
	created_ms, updated_ms: i64,
	max_body_bytes: int,
) -> Paste_Codec_Error {
	if !paste_max_body_is_valid(max_body_bytes) {
		return .Invalid_Input
	}
	if len(title) < 1 || len(title) > PASTE_TITLE_MAX_BYTES || !utf8.valid_string(title) {
		return .Invalid_Input
	}
	for c in title {
		if c == 0 || c == '\r' || c == '\n' {
			return .Invalid_Input
		}
	}
	if len(body) > max_body_bytes {
		return .Too_Large
	}
	if !utf8.valid_string(body) || created_ms < 0 || updated_ms < created_ms {
		return .Invalid_Input
	}
	return .None
}

paste_plaintext_encode :: proc(
	title, body: string,
	created_ms, updated_ms: i64,
	max_body_bytes: int,
	allocator: mem.Allocator,
) -> ([]byte, Paste_Codec_Error) {
	if validation_err := paste_document_fields_are_valid(title, body, created_ms, updated_ms, max_body_bytes); validation_err != .None {
		return nil, validation_err
	}
	total_u64 := u64(PASTE_PLAINTEXT_HEADER_BYTES) + u64(len(title)) + u64(len(body))
	if total_u64 > u64(max(int)) {
		return nil, .Too_Large
	}
	plaintext, alloc_err := make([]byte, int(total_u64), allocator)
	if alloc_err != nil {
		return nil, .Allocation
	}
	magic: [4]byte = PASTE_PLAINTEXT_MAGIC
	copy(plaintext[0:4], magic[:])
	endian.unchecked_put_u32be(plaintext[4:8], u32(len(title)))
	endian.unchecked_put_u32be(plaintext[8:12], u32(len(body)))
	endian.unchecked_put_u64be(plaintext[12:20], u64(created_ms))
	endian.unchecked_put_u64be(plaintext[20:28], u64(updated_ms))
	offset := PASTE_PLAINTEXT_HEADER_BYTES
	offset += copy(plaintext[offset:], title)
	copy(plaintext[offset:], body)
	return plaintext, .None
}

paste_fill_aad :: proc(dst: ^[PASTE_AAD_MAX_BYTES]byte, kid: string, pid: []byte) -> ([]byte, bool) {
	if dst == nil || !paste_key_id_is_valid(kid) || len(pid) != PASTE_PID_BYTES {
		return nil, false
	}
	offset := 0
	offset += copy(dst[offset:], PASTE_AAD_PURPOSE)
	dst[offset] = 0
	offset += 1
	dst[offset] = byte(PASTE_V1_VERSION)
	offset += 1
	dst[offset] = PASTE_V1_ALGORITHM_ID
	offset += 1
	dst[offset] = byte(len(kid))
	offset += 1
	offset += copy(dst[offset:], kid)
	offset += copy(dst[offset:], pid)
	return dst[:offset], true
}

paste_encode_lower_hex_into :: proc(dst: []byte, src: []byte) -> bool {
	lower: string = "0123456789abcdef"
	if len(dst) != len(src) * 2 {
		return false
	}
	for value, i in src {
		dst[i * 2] = lower[value >> 4]
		dst[i * 2 + 1] = lower[value & 0x0f]
	}
	return true
}

paste_envelope_size :: proc(kid_length, ciphertext_bytes: int) -> (int, bool) {
	if kid_length < 1 || kid_length > PASTE_KEY_ID_MAX_BYTES || ciphertext_bytes < 0 {
		return 0, false
	}
	fixed := len(PASTE_ENVELOPE_PREFIX) + len(PASTE_ENVELOPE_PID_SEPARATOR) +
		len(PASTE_ENVELOPE_NONCE_SEPARATOR) + len(PASTE_ENVELOPE_CIPHER_SEPARATOR) +
		len(PASTE_ENVELOPE_TAG_SEPARATOR) + len(PASTE_ENVELOPE_SUFFIX) +
		PASTE_PID_BYTES * 2 + PASTE_NONCE_BYTES * 2 + PASTE_TAG_BYTES * 2
	if ciphertext_bytes > (max(int) - fixed - kid_length) / 2 {
		return 0, false
	}
	return fixed + kid_length + ciphertext_bytes * 2, true
}

paste_envelope_encode :: proc(
	key: ^Paste_Key,
	pid, nonce, ciphertext, tag: []byte,
	allocator: mem.Allocator,
) -> (string, Paste_Codec_Error) {
	if key == nil || !paste_key_id_is_valid(key.id) || len(pid) != PASTE_PID_BYTES ||
	   len(nonce) != PASTE_NONCE_BYTES || len(tag) != PASTE_TAG_BYTES {
		return "", .Invalid_Input
	}
	total, size_ok := paste_envelope_size(len(key.id), len(ciphertext))
	if !size_ok {
		return "", .Too_Large
	}
	encoded, alloc_err := make([]byte, total, allocator)
	if alloc_err != nil {
		return "", .Allocation
	}
	offset := 0
	offset += copy(encoded[offset:], PASTE_ENVELOPE_PREFIX)
	offset += copy(encoded[offset:], key.id)
	offset += copy(encoded[offset:], PASTE_ENVELOPE_PID_SEPARATOR)
	paste_encode_lower_hex_into(encoded[offset:offset + len(pid) * 2], pid)
	offset += len(pid) * 2
	offset += copy(encoded[offset:], PASTE_ENVELOPE_NONCE_SEPARATOR)
	paste_encode_lower_hex_into(encoded[offset:offset + len(nonce) * 2], nonce)
	offset += len(nonce) * 2
	offset += copy(encoded[offset:], PASTE_ENVELOPE_CIPHER_SEPARATOR)
	paste_encode_lower_hex_into(encoded[offset:offset + len(ciphertext) * 2], ciphertext)
	offset += len(ciphertext) * 2
	offset += copy(encoded[offset:], PASTE_ENVELOPE_TAG_SEPARATOR)
	paste_encode_lower_hex_into(encoded[offset:offset + len(tag) * 2], tag)
	offset += len(tag) * 2
	offset += copy(encoded[offset:], PASTE_ENVELOPE_SUFFIX)
	assert(offset == len(encoded))
	return string(encoded), .None
}

paste_encrypt_with_nonce :: proc(
	codec: ^Paste_Codec,
	key: ^Paste_Key,
	pid, nonce: []byte,
	title, body: string,
	created_ms, updated_ms: i64,
	max_body_bytes: int,
	allocator: mem.Allocator,
) -> (string, Paste_Codec_Error) {
	if codec == nil || codec.keys == nil || key == nil {
		return "", .Invalid_Input
	}
	plaintext, plaintext_err := paste_plaintext_encode(
		title, body, created_ms, updated_ms, max_body_bytes, allocator,
	)
	if plaintext_err != .None {
		return "", plaintext_err
	}
	defer {
		paste_wipe_bytes(plaintext)
		delete(plaintext, allocator)
	}

	ciphertext, cipher_alloc_err := make([]byte, len(plaintext), allocator)
	if cipher_alloc_err != nil {
		return "", .Allocation
	}
	defer {
		paste_wipe_bytes(ciphertext)
		delete(ciphertext, allocator)
	}

	tag: [PASTE_TAG_BYTES]byte
	defer crypto.zero_explicit(raw_data(tag[:]), len(tag))
	aad_storage: [PASTE_AAD_MAX_BYTES]byte
	defer crypto.zero_explicit(raw_data(aad_storage[:]), len(aad_storage))
	aad, aad_ok := paste_fill_aad(&aad_storage, key.id, pid)
	if !aad_ok || len(nonce) != PASTE_NONCE_BYTES {
		return "", .Invalid_Input
	}
	aead.seal_oneshot(
		.XCHACHA20POLY1305,
		ciphertext,
		tag[:],
		key.material[:],
		nonce,
		aad,
		plaintext,
	)
	return paste_envelope_encode(key, pid, nonce, ciphertext, tag[:], allocator)
}

paste_encrypt_new :: proc(
	codec: ^Paste_Codec,
	title, body: string,
	now_ms: i64,
	max_body_bytes: int,
	allocator: mem.Allocator = context.temp_allocator,
) -> (envelope_json, pid: string, err: Paste_Codec_Error) {
	if codec == nil || codec.keys == nil || codec.keys.active == nil {
		return "", "", .Invalid_Input
	}
	if validation_err := paste_document_fields_are_valid(title, body, now_ms, now_ms, max_body_bytes); validation_err != .None {
		return "", "", validation_err
	}

	random: [PASTE_PID_BYTES + PASTE_NONCE_BYTES]byte
	crypto.rand_bytes(random[:])
	defer crypto.zero_explicit(raw_data(random[:]), len(random))

	pid_encoded, pid_alloc_err := make([]byte, PASTE_PID_BYTES * 2, allocator)
	if pid_alloc_err != nil {
		return "", "", .Allocation
	}
	paste_encode_lower_hex_into(pid_encoded, random[:PASTE_PID_BYTES])
	pid = string(pid_encoded)
	envelope_json, err = paste_encrypt_with_nonce(
		codec,
		codec.keys.active,
		random[:PASTE_PID_BYTES],
		random[PASTE_PID_BYTES:],
		title,
		body,
		now_ms,
		now_ms,
		max_body_bytes,
		allocator,
	)
	if err != .None {
		paste_wipe_bytes(pid_encoded)
		delete(pid_encoded, allocator)
		return "", "", err
	}
	return
}

paste_encrypt_existing :: proc(
	codec: ^Paste_Codec,
	pid: string,
	doc: ^Paste_Document,
	max_body_bytes: int,
	allocator: mem.Allocator = context.temp_allocator,
) -> (string, Paste_Codec_Error) {
	if codec == nil || codec.keys == nil || codec.keys.active == nil || doc == nil {
		return "", .Invalid_Input
	}
	if !paste_lower_hex_is_valid(pid, PASTE_PID_BYTES * 2) {
		return "", .Invalid_Input
	}
	if validation_err := paste_document_fields_are_valid(
		doc.title, doc.body, doc.created_ms, doc.updated_ms, max_body_bytes,
	); validation_err != .None {
		return "", validation_err
	}

	pid_bytes, pid_err := paste_decode_lower_hex(pid, allocator)
	if pid_err != .None {
		return "", .Invalid_Input if pid_err == .Invalid_Envelope else pid_err
	}
	defer {
		paste_wipe_bytes(pid_bytes)
		delete(pid_bytes, allocator)
	}
	nonce: [PASTE_NONCE_BYTES]byte
	crypto.rand_bytes(nonce[:])
	defer crypto.zero_explicit(raw_data(nonce[:]), len(nonce))

	return paste_encrypt_with_nonce(
		codec,
		codec.keys.active,
		pid_bytes,
		nonce[:],
		doc.title,
		doc.body,
		doc.created_ms,
		doc.updated_ms,
		max_body_bytes,
		allocator,
	)
}

paste_json_is_space :: proc(c: byte) -> bool {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

paste_json_skip_space :: proc(input: string, index: ^int) {
	for index^ < len(input) && paste_json_is_space(input[index^]) {
		index^ += 1
	}
}

// Envelope values are deliberately restricted to the unescaped ASCII subset
// generated by paste_envelope_encode. This rejects alternate spellings rather
// than introducing a second serialization format.
paste_json_plain_string :: proc(input: string, index: ^int) -> (string, bool) {
	if index^ >= len(input) || input[index^] != '"' {
		return "", false
	}
	index^ += 1
	start := index^
	for index^ < len(input) {
		c := input[index^]
		if c == '"' {
			value := input[start:index^]
			index^ += 1
			return value, true
		}
		if c == '\\' || c < 0x20 || c >= 0x80 {
			return "", false
		}
		index^ += 1
	}
	return "", false
}

paste_json_integer :: proc(input: string, index: ^int) -> (int, bool, bool) {
	start := index^
	if index^ < len(input) && input[index^] == '-' {
		index^ += 1
	}
	digits_start := index^
	if index^ >= len(input) || input[index^] < '0' || input[index^] > '9' {
		return 0, false, false
	}
	if input[index^] == '0' {
		index^ += 1
		if index^ < len(input) && '0' <= input[index^] && input[index^] <= '9' {
			return 0, false, false
		}
	} else {
		for index^ < len(input) && '0' <= input[index^] && input[index^] <= '9' {
			index^ += 1
		}
	}
	if index^ == digits_start {
		return 0, false, false
	}
	value, representable := strconv.parse_int(input[start:index^], 10)
	return value, true, representable
}

// This zero-allocation pass rejects duplicate/unknown fields, wrong JSON
// types, trailing data, and non-canonical escaped secret spellings before a
// loader unmarshals the DTO with its owned allocator.
paste_secrets_json_validate :: proc(input: string) -> Paste_Secrets_Error {
	i := 0
	paste_json_skip_space(input, &i)
	if i >= len(input) || input[i] != '{' {
		return .Invalid_JSON
	}
	i += 1
	seen: u8
	github_gist_token := ""
	active_key_id := ""
	key_ids: [PASTE_KEYRING_MAX_KEYS]string
	key_materials: [PASTE_KEYRING_MAX_KEYS]string
	key_count := 0

	for {
		paste_json_skip_space(input, &i)
		if i < len(input) && input[i] == '}' {
			i += 1
			break
		}
		field, field_ok := paste_json_plain_string(input, &i)
		if !field_ok {
			return .Invalid_JSON
		}
		paste_json_skip_space(input, &i)
		if i >= len(input) || input[i] != ':' {
			return .Invalid_JSON
		}
		i += 1
		paste_json_skip_space(input, &i)

		bit: u8
		switch field {
		case "github_gist_token":
			bit = 1 << 0
			github_gist_token, field_ok = paste_json_plain_string(input, &i)
		case "active_key_id":
			bit = 1 << 1
			active_key_id, field_ok = paste_json_plain_string(input, &i)
		case "keys":
			bit = 1 << 2
			if i >= len(input) || input[i] != '[' {
				return .Invalid_JSON
			}
			i += 1
			paste_json_skip_space(input, &i)
			if i < len(input) && input[i] == ']' {
				i += 1
			} else {
				for {
					if key_count >= PASTE_KEYRING_MAX_KEYS {
						return .Invalid_Key_Count
					}
					if i >= len(input) || input[i] != '{' {
						return .Invalid_JSON
					}
					i += 1
					key_seen: u8
					key_id := ""
					key_material := ""

					for {
						paste_json_skip_space(input, &i)
						if i < len(input) && input[i] == '}' {
							i += 1
							break
						}
						key_field, key_field_ok := paste_json_plain_string(input, &i)
						if !key_field_ok {
							return .Invalid_JSON
						}
						paste_json_skip_space(input, &i)
						if i >= len(input) || input[i] != ':' {
							return .Invalid_JSON
						}
						i += 1
						paste_json_skip_space(input, &i)

						key_bit: u8
						switch key_field {
						case "id":
							key_bit = 1 << 0
							key_id, key_field_ok = paste_json_plain_string(input, &i)
						case "key_hex":
							key_bit = 1 << 1
							key_material, key_field_ok = paste_json_plain_string(input, &i)
						case:
							return .Invalid_Shape
						}
						if !key_field_ok {
							return .Invalid_JSON
						}
						if key_seen & key_bit != 0 {
							return .Invalid_Shape
						}
						key_seen |= key_bit

						paste_json_skip_space(input, &i)
						if i < len(input) && input[i] == ',' {
							i += 1
							paste_json_skip_space(input, &i)
							if i >= len(input) || input[i] == '}' {
								return .Invalid_JSON
							}
							continue
						}
						if i < len(input) && input[i] == '}' {
							i += 1
							break
						}
						return .Invalid_JSON
					}
					if key_seen != 0x03 {
						return .Invalid_Shape
					}
					if !paste_key_id_is_valid(key_id) {
						return .Invalid_Key_Id
					}
					if !paste_lower_hex_is_valid(key_material, PASTE_KEY_BYTES * 2) {
						return .Invalid_Key_Material
					}
					for previous in 0..<key_count {
						if key_ids[previous] == key_id {
							return .Duplicate_Key_Id
						}
						if crypto.compare_constant_time(
							transmute([]byte)key_materials[previous],
							transmute([]byte)key_material,
						) == 1 {
							return .Duplicate_Key_Material
						}
					}
					key_ids[key_count] = key_id
					key_materials[key_count] = key_material
					key_count += 1

					paste_json_skip_space(input, &i)
					if i < len(input) && input[i] == ',' {
						i += 1
						paste_json_skip_space(input, &i)
						if i >= len(input) || input[i] == ']' {
							return .Invalid_JSON
						}
						continue
					}
					if i < len(input) && input[i] == ']' {
						i += 1
						break
					}
					return .Invalid_JSON
				}
			}
		case:
			return .Invalid_Shape
		}
		if !field_ok {
			return .Invalid_JSON
		}
		if seen & bit != 0 {
			return .Invalid_Shape
		}
		seen |= bit

		paste_json_skip_space(input, &i)
		if i < len(input) && input[i] == ',' {
			i += 1
			paste_json_skip_space(input, &i)
			if i >= len(input) || input[i] == '}' {
				return .Invalid_JSON
			}
			continue
		}
		if i < len(input) && input[i] == '}' {
			i += 1
			break
		}
		return .Invalid_JSON
	}

	paste_json_skip_space(input, &i)
	if i != len(input) {
		return .Invalid_JSON
	}
	if seen != 0x07 {
		return .Invalid_Shape
	}
	if !paste_secret_token_is_valid(github_gist_token) {
		return .Empty_Token
	}
	if key_count < 1 {
		return .Invalid_Key_Count
	}
	if !paste_key_id_is_valid(active_key_id) {
		return .Missing_Active_Key
	}
	for key_id in key_ids[:key_count] {
		if key_id == active_key_id {
			return .None
		}
	}
	return .Missing_Active_Key
}

paste_envelope_parse :: proc(input: string, max_body_bytes: int) -> (Paste_Envelope_V1, Paste_Codec_Error) {
	envelope: Paste_Envelope_V1
	if !paste_max_body_is_valid(max_body_bytes) {
		return envelope, .Invalid_Input
	}
	max_clear := PASTE_PLAINTEXT_HEADER_BYTES + PASTE_TITLE_MAX_BYTES + max_body_bytes
	max_envelope, size_ok := paste_envelope_size(PASTE_KEY_ID_MAX_BYTES, max_clear)
	if !size_ok || len(input) > max_envelope {
		return envelope, .Too_Large
	}

	i := 0
	paste_json_skip_space(input, &i)
	if i >= len(input) || input[i] != '{' {
		return envelope, .Invalid_Envelope
	}
	i += 1
	seen: u8
	field_count := 0
	for {
		paste_json_skip_space(input, &i)
		if i < len(input) && input[i] == '}' {
			i += 1
			break
		}
		key, key_ok := paste_json_plain_string(input, &i)
		if !key_ok {
			return envelope, .Invalid_Envelope
		}
		paste_json_skip_space(input, &i)
		if i >= len(input) || input[i] != ':' {
			return envelope, .Invalid_Envelope
		}
		i += 1
		paste_json_skip_space(input, &i)

		bit: u8
		switch key {
		case "v":
			bit = 1 << 0
			value, syntax_ok, representable := paste_json_integer(input, &i)
			if !syntax_ok {
				return envelope, .Invalid_Envelope
			}
			envelope.v = value if representable else 0
		case "alg":
			bit = 1 << 1
			envelope.alg, key_ok = paste_json_plain_string(input, &i)
		case "kid":
			bit = 1 << 2
			envelope.kid, key_ok = paste_json_plain_string(input, &i)
		case "pid":
			bit = 1 << 3
			envelope.pid, key_ok = paste_json_plain_string(input, &i)
		case "nonce":
			bit = 1 << 4
			envelope.nonce, key_ok = paste_json_plain_string(input, &i)
		case "ciphertext":
			bit = 1 << 5
			envelope.ciphertext, key_ok = paste_json_plain_string(input, &i)
		case "tag":
			bit = 1 << 6
			envelope.tag, key_ok = paste_json_plain_string(input, &i)
		case:
			return envelope, .Invalid_Envelope
		}
		if !key_ok || seen & bit != 0 {
			return envelope, .Invalid_Envelope
		}
		seen |= bit
		field_count += 1

		paste_json_skip_space(input, &i)
		if i < len(input) && input[i] == ',' {
			i += 1
			paste_json_skip_space(input, &i)
			if i >= len(input) || input[i] == '}' {
				return envelope, .Invalid_Envelope
			}
			continue
		}
		if i < len(input) && input[i] == '}' {
			i += 1
			break
		}
		return envelope, .Invalid_Envelope
	}
	paste_json_skip_space(input, &i)
	if i != len(input) || field_count != 7 || seen != 0x7f {
		return envelope, .Invalid_Envelope
	}
	if envelope.v != PASTE_V1_VERSION {
		return envelope, .Unsupported_Version
	}
	if envelope.alg != PASTE_V1_ALGORITHM_NAME {
		return envelope, .Unsupported_Algorithm
	}
	if !paste_key_id_is_valid(envelope.kid) ||
	   !paste_lower_hex_is_valid(envelope.pid, PASTE_PID_BYTES * 2) ||
	   !paste_lower_hex_is_valid(envelope.nonce, PASTE_NONCE_BYTES * 2) ||
	   !paste_lower_hex_is_valid(envelope.tag, PASTE_TAG_BYTES * 2) {
		return envelope, .Invalid_Envelope
	}
	if len(envelope.ciphertext) % 2 != 0 ||
	   !paste_lower_hex_is_valid(envelope.ciphertext, len(envelope.ciphertext)) {
		return envelope, .Invalid_Envelope
	}
	clear_length := len(envelope.ciphertext) / 2
	if clear_length < PASTE_PLAINTEXT_HEADER_BYTES + 1 {
		return envelope, .Invalid_Envelope
	}
	if clear_length > max_clear {
		return envelope, .Too_Large
	}
	return envelope, .None
}

paste_plaintext_decode :: proc(
	storage: []byte,
	max_body_bytes: int,
) -> (Paste_Document, Paste_Codec_Error) {
	doc: Paste_Document
	if len(storage) < PASTE_PLAINTEXT_HEADER_BYTES + 1 || !paste_max_body_is_valid(max_body_bytes) {
		return doc, .Invalid_Envelope
	}
	if storage[0] != PASTE_PLAINTEXT_MAGIC[0] || storage[1] != PASTE_PLAINTEXT_MAGIC[1] ||
	   storage[2] != PASTE_PLAINTEXT_MAGIC[2] || storage[3] != PASTE_PLAINTEXT_MAGIC[3] {
		return doc, .Invalid_Envelope
	}
	title_length := endian.unchecked_get_u32be(storage[4:8])
	body_length := endian.unchecked_get_u32be(storage[8:12])
	created_ms := i64(endian.unchecked_get_u64be(storage[12:20]))
	updated_ms := i64(endian.unchecked_get_u64be(storage[20:28]))
	total := u64(PASTE_PLAINTEXT_HEADER_BYTES) + u64(title_length) + u64(body_length)
	if total != u64(len(storage)) || title_length < 1 || title_length > PASTE_TITLE_MAX_BYTES {
		return doc, .Invalid_Envelope
	}
	if u64(body_length) > u64(max_body_bytes) {
		return doc, .Too_Large
	}
	title_end := PASTE_PLAINTEXT_HEADER_BYTES + int(title_length)
	title := string(storage[PASTE_PLAINTEXT_HEADER_BYTES:title_end])
	body := string(storage[title_end:])
	if validation_err := paste_document_fields_are_valid(
		title, body, created_ms, updated_ms, max_body_bytes,
	); validation_err != .None {
		return doc, .Invalid_Envelope if validation_err == .Invalid_Input else validation_err
	}
	doc = {
		title      = title,
		body       = body,
		created_ms = created_ms,
		updated_ms = updated_ms,
		storage    = storage,
	}
	return doc, .None
}

paste_decrypt :: proc(
	codec: ^Paste_Codec,
	envelope_json: string,
	max_body_bytes: int,
	allocator: mem.Allocator = context.temp_allocator,
) -> (Paste_Document, Paste_Envelope_V1, Paste_Codec_Error) {
	empty_doc: Paste_Document
	envelope, envelope_err := paste_envelope_parse(envelope_json, max_body_bytes)
	if envelope_err != .None {
		return empty_doc, envelope, envelope_err
	}
	if codec == nil || codec.keys == nil || codec.keys.by_id == nil {
		return empty_doc, envelope, .Invalid_Input
	}
	key, found := codec.keys.by_id[envelope.kid]
	if !found || key == nil {
		return empty_doc, envelope, .Key_Unavailable
	}

	pid, pid_err := paste_decode_lower_hex(envelope.pid, allocator)
	if pid_err != .None {
		return empty_doc, envelope, pid_err
	}
	defer {
		paste_wipe_bytes(pid)
		delete(pid, allocator)
	}
	nonce, nonce_err := paste_decode_lower_hex(envelope.nonce, allocator)
	if nonce_err != .None {
		return empty_doc, envelope, nonce_err
	}
	defer {
		paste_wipe_bytes(nonce)
		delete(nonce, allocator)
	}
	tag, tag_err := paste_decode_lower_hex(envelope.tag, allocator)
	if tag_err != .None {
		return empty_doc, envelope, tag_err
	}
	defer {
		paste_wipe_bytes(tag)
		delete(tag, allocator)
	}
	ciphertext, ciphertext_err := paste_decode_lower_hex(envelope.ciphertext, allocator)
	if ciphertext_err != .None {
		return empty_doc, envelope, ciphertext_err
	}
	defer {
		paste_wipe_bytes(ciphertext)
		delete(ciphertext, allocator)
	}

	plaintext, plaintext_alloc_err := make([]byte, len(ciphertext), allocator)
	if plaintext_alloc_err != nil {
		return empty_doc, envelope, .Allocation
	}
	aad_storage: [PASTE_AAD_MAX_BYTES]byte
	defer crypto.zero_explicit(raw_data(aad_storage[:]), len(aad_storage))
	aad, aad_ok := paste_fill_aad(&aad_storage, envelope.kid, pid)
	if !aad_ok {
		paste_wipe_bytes(plaintext)
		delete(plaintext, allocator)
		return empty_doc, envelope, .Invalid_Envelope
	}
	if !aead.open_oneshot(
		.XCHACHA20POLY1305,
		plaintext,
		key.material[:],
		nonce,
		aad,
		ciphertext,
		tag,
	) {
		paste_wipe_bytes(plaintext)
		delete(plaintext, allocator)
		return empty_doc, envelope, .Authentication_Failed
	}

	doc, plaintext_err := paste_plaintext_decode(plaintext, max_body_bytes)
	if plaintext_err != .None {
		paste_wipe_bytes(plaintext)
		delete(plaintext, allocator)
		return empty_doc, envelope, plaintext_err
	}
	return doc, envelope, .None
}

// Rotation authenticates exactly once with the envelope-selected key, then
// writes with the active key and a fresh server-generated nonce. It never
// tries another key after authentication failure.
paste_rotate :: proc(
	codec: ^Paste_Codec,
	envelope_json: string,
	max_body_bytes: int,
	allocator: mem.Allocator = context.temp_allocator,
) -> (string, Paste_Codec_Error) {
	doc, envelope, decrypt_err := paste_decrypt(codec, envelope_json, max_body_bytes, allocator)
	if decrypt_err != .None {
		return "", decrypt_err
	}
	defer paste_document_destroy(&doc, allocator)
	return paste_encrypt_existing(codec, envelope.pid, &doc, max_body_bytes, allocator)
}

paste_document_destroy :: proc(
	doc: ^Paste_Document,
	allocator: mem.Allocator = context.temp_allocator,
) {
	if doc == nil {
		return
	}
	if doc.storage != nil {
		paste_wipe_bytes(doc.storage)
		delete(doc.storage, allocator)
	}
	doc^ = {}
}

@(test)
test_paste_v1_round_trip_and_randomization :: proc(t: ^testing.T) {
	allocator := context.allocator
	key_configs: [1]Paste_Key_Config
	key_configs[0] = {
		id      = "test-v1",
		key_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
	}
	secrets := Paste_Secrets_Config{
		github_gist_token = "test-token",
		active_key_id     = "test-v1",
		keys              = key_configs[:],
	}
	keyring: Paste_Keyring
	keyring_err := paste_keyring_init(&keyring, &secrets, allocator)
	testing.expect(t, keyring_err == .None)
	if keyring_err != .None {
		return
	}
	defer paste_keyring_destroy(&keyring, allocator)
	codec: Paste_Codec
	codec_err := paste_codec_init(&codec, &keyring)
	testing.expect(t, codec_err == .None)
	if codec_err != .None {
		return
	}
	defer paste_codec_destroy(&codec)

	empty_envelope, empty_pid, empty_err := paste_encrypt_new(
		&codec, "Résumé 🔐", "", 1_700_000_000_000, 64, allocator,
	)
	testing.expect(t, empty_err == .None)
	if empty_err != .None {
		return
	}
	defer {
		paste_wipe_string(empty_envelope)
		delete(empty_envelope, allocator)
		paste_wipe_string(empty_pid)
		delete(empty_pid, allocator)
	}
	empty_doc, empty_parsed, empty_decrypt_err := paste_decrypt(&codec, empty_envelope, 64, allocator)
	testing.expect(t, empty_decrypt_err == .None)
	if empty_decrypt_err != .None {
		return
	}
	defer paste_document_destroy(&empty_doc, allocator)
	testing.expect(t, empty_parsed.v == PASTE_V1_VERSION)
	testing.expect(t, empty_parsed.pid == empty_pid)
	testing.expect(t, empty_doc.title == "Résumé 🔐")
	testing.expect(t, empty_doc.body == "")
	testing.expect(t, empty_doc.created_ms == 1_700_000_000_000)
	testing.expect(t, empty_doc.updated_ms == empty_doc.created_ms)

	utf8_envelope, utf8_pid, utf8_err := paste_encrypt_new(
		&codec, "Unicode", "Zażółć gęślą jaźń — 東京", 1_700_000_000_001, 128, allocator,
	)
	testing.expect(t, utf8_err == .None)
	if utf8_err != .None {
		return
	}
	defer {
		paste_wipe_string(utf8_envelope)
		delete(utf8_envelope, allocator)
		paste_wipe_string(utf8_pid)
		delete(utf8_pid, allocator)
	}
	utf8_doc, _, utf8_decrypt_err := paste_decrypt(&codec, utf8_envelope, 128, allocator)
	testing.expect(t, utf8_decrypt_err == .None)
	if utf8_decrypt_err != .None {
		return
	}
	defer paste_document_destroy(&utf8_doc, allocator)
	testing.expect(t, utf8_doc.title == "Unicode")
	testing.expect(t, utf8_doc.body == "Zażółć gęślą jaźń — 東京")

	first, first_pid, first_err := paste_encrypt_new(&codec, "Same", "same plaintext", 42, 64, allocator)
	testing.expect(t, first_err == .None)
	if first_err != .None {
		return
	}
	defer {
		paste_wipe_string(first)
		delete(first, allocator)
		paste_wipe_string(first_pid)
		delete(first_pid, allocator)
	}
	second, second_pid, second_err := paste_encrypt_new(&codec, "Same", "same plaintext", 42, 64, allocator)
	testing.expect(t, second_err == .None)
	if second_err != .None {
		return
	}
	defer {
		paste_wipe_string(second)
		delete(second, allocator)
		paste_wipe_string(second_pid)
		delete(second_pid, allocator)
	}
	first_parsed, first_parse_err := paste_envelope_parse(first, 64)
	second_parsed, second_parse_err := paste_envelope_parse(second, 64)
	testing.expect(t, first_parse_err == .None)
	testing.expect(t, second_parse_err == .None)
	if first_parse_err == .None && second_parse_err == .None {
		testing.expect(t, first_parsed.nonce != second_parsed.nonce)
		testing.expect(t, first_parsed.ciphertext != second_parsed.ciphertext)
	}
}

@(test)
test_paste_authenticated_fields_and_unknown_key :: proc(t: ^testing.T) {
	allocator := context.allocator
	old_configs: [1]Paste_Key_Config
	old_configs[0] = {
		id      = "old",
		key_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
	}
	old_secrets := Paste_Secrets_Config{
		github_gist_token = "test-token",
		active_key_id     = "old",
		keys              = old_configs[:],
	}
	old_keyring: Paste_Keyring
	old_keyring_err := paste_keyring_init(&old_keyring, &old_secrets, allocator)
	testing.expect(t, old_keyring_err == .None)
	if old_keyring_err != .None {
		return
	}
	defer paste_keyring_destroy(&old_keyring, allocator)
	old_codec: Paste_Codec
	if paste_codec_init(&old_codec, &old_keyring) != .None {
		testing.expect(t, false)
		return
	}
	defer paste_codec_destroy(&old_codec)

	envelope, pid, encrypt_err := paste_encrypt_new(&old_codec, "Authenticated", "payload", 99, 64, allocator)
	testing.expect(t, encrypt_err == .None)
	if encrypt_err != .None {
		return
	}
	defer {
		paste_wipe_string(envelope)
		delete(envelope, allocator)
		paste_wipe_string(pid)
		delete(pid, allocator)
	}
	parsed, parse_err := paste_envelope_parse(envelope, 64)
	testing.expect(t, parse_err == .None)
	if parse_err != .None {
		return
	}
	pid_offset := len(PASTE_ENVELOPE_PREFIX) + len(parsed.kid) + len(PASTE_ENVELOPE_PID_SEPARATOR)
	nonce_offset := pid_offset + PASTE_PID_BYTES * 2 + len(PASTE_ENVELOPE_NONCE_SEPARATOR)
	cipher_offset := nonce_offset + PASTE_NONCE_BYTES * 2 + len(PASTE_ENVELOPE_CIPHER_SEPARATOR)
	tag_offset := cipher_offset + len(parsed.ciphertext) + len(PASTE_ENVELOPE_TAG_SEPARATOR)
	offsets := [3]int{pid_offset, cipher_offset, tag_offset}
	for offset in offsets {
		tampered, clone_err := strings.clone(envelope, allocator)
		testing.expect(t, clone_err == nil)
		if clone_err != nil {
			continue
		}
		tampered_bytes := transmute([]byte)tampered
		tampered_bytes[offset] = '1' if tampered_bytes[offset] == '0' else '0'
		tampered_doc, _, tampered_err := paste_decrypt(&old_codec, tampered, 64, allocator)
		testing.expect(t, tampered_err == .Authentication_Failed)
		paste_document_destroy(&tampered_doc, allocator)
		paste_wipe_string(tampered)
		delete(tampered, allocator)
	}

	new_configs: [1]Paste_Key_Config
	new_configs[0] = {
		id      = "new",
		key_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
	}
	new_secrets := Paste_Secrets_Config{
		github_gist_token = "test-token",
		active_key_id     = "new",
		keys              = new_configs[:],
	}
	new_keyring: Paste_Keyring
	new_keyring_err := paste_keyring_init(&new_keyring, &new_secrets, allocator)
	testing.expect(t, new_keyring_err == .None)
	if new_keyring_err != .None {
		return
	}
	defer paste_keyring_destroy(&new_keyring, allocator)
	new_codec: Paste_Codec
	if paste_codec_init(&new_codec, &new_keyring) != .None {
		testing.expect(t, false)
		return
	}
	defer paste_codec_destroy(&new_codec)
	unknown_doc, _, unknown_err := paste_decrypt(&new_codec, envelope, 64, allocator)
	testing.expect(t, unknown_err == .Key_Unavailable)
	paste_document_destroy(&unknown_doc, allocator)
}

@(test)
test_paste_edit_and_rotation_invariants :: proc(t: ^testing.T) {
	allocator := context.allocator
	key_configs: [2]Paste_Key_Config
	key_configs[0] = {
		id      = "old",
		key_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
	}
	key_configs[1] = {
		id      = "new",
		key_hex = "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
	}
	secrets := Paste_Secrets_Config{
		github_gist_token = "test-token",
		active_key_id     = "old",
		keys              = key_configs[:],
	}
	keyring: Paste_Keyring
	keyring_err := paste_keyring_init(&keyring, &secrets, allocator)
	testing.expect(t, keyring_err == .None)
	if keyring_err != .None {
		return
	}
	defer paste_keyring_destroy(&keyring, allocator)
	codec: Paste_Codec
	if paste_codec_init(&codec, &keyring) != .None {
		testing.expect(t, false)
		return
	}
	defer paste_codec_destroy(&codec)

	original, original_pid, original_err := paste_encrypt_new(&codec, "Before", "first", 1_000, 64, allocator)
	testing.expect(t, original_err == .None)
	if original_err != .None {
		return
	}
	defer {
		paste_wipe_string(original)
		delete(original, allocator)
		paste_wipe_string(original_pid)
		delete(original_pid, allocator)
	}
	doc, original_parsed, decrypt_err := paste_decrypt(&codec, original, 64, allocator)
	testing.expect(t, decrypt_err == .None)
	if decrypt_err != .None {
		return
	}
	defer paste_document_destroy(&doc, allocator)
	doc.title = "After"
	doc.body = "second"
	doc.updated_ms = 2_000
	edited, edited_err := paste_encrypt_existing(&codec, original_parsed.pid, &doc, 64, allocator)
	testing.expect(t, edited_err == .None)
	if edited_err != .None {
		return
	}
	defer {
		paste_wipe_string(edited)
		delete(edited, allocator)
	}
	edited_doc, edited_parsed, edited_decrypt_err := paste_decrypt(&codec, edited, 64, allocator)
	testing.expect(t, edited_decrypt_err == .None)
	if edited_decrypt_err != .None {
		return
	}
	defer paste_document_destroy(&edited_doc, allocator)
	testing.expect(t, edited_parsed.pid == original_parsed.pid)
	testing.expect(t, edited_doc.created_ms == 1_000)
	testing.expect(t, edited_doc.updated_ms == 2_000)
	testing.expect(t, edited_doc.title == "After")
	testing.expect(t, edited_doc.body == "second")

	new_active, found := keyring.by_id["new"]
	testing.expect(t, found && new_active != nil)
	if !found || new_active == nil {
		return
	}
	keyring.active = new_active
	rotated, rotate_err := paste_rotate(&codec, edited, 64, allocator)
	testing.expect(t, rotate_err == .None)
	if rotate_err != .None {
		return
	}
	defer {
		paste_wipe_string(rotated)
		delete(rotated, allocator)
	}
	rotated_doc, rotated_parsed, rotated_decrypt_err := paste_decrypt(&codec, rotated, 64, allocator)
	testing.expect(t, rotated_decrypt_err == .None)
	if rotated_decrypt_err != .None {
		return
	}
	defer paste_document_destroy(&rotated_doc, allocator)
	testing.expect(t, rotated_parsed.kid == "new")
	testing.expect(t, rotated_parsed.pid == edited_parsed.pid)
	testing.expect(t, rotated_parsed.nonce != edited_parsed.nonce)
	testing.expect(t, rotated_doc.title == edited_doc.title)
	testing.expect(t, rotated_doc.body == edited_doc.body)
	testing.expect(t, rotated_doc.created_ms == edited_doc.created_ms)
	testing.expect(t, rotated_doc.updated_ms == edited_doc.updated_ms)
}

@(test)
test_paste_rejects_invalid_shapes_and_bounds :: proc(t: ^testing.T) {
	allocator := context.allocator
	material_a := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
	material_b := "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"

	testing.expect(t, paste_secrets_json_validate("{}") == .Invalid_Shape)
	testing.expect(t, paste_secrets_json_validate(`{"github_gist_token":"token","active_key_id":"a","keys":[{"id":"a"}]}`) == .Invalid_Shape)
	testing.expect(t, paste_secrets_json_validate(`{"github_gist_token":"token","active_key_id":"a","keys":[],"extra":"x"}`) == .Invalid_Shape)

	testing.expect(t, paste_secrets_validate(nil) == .Empty_Token)
	empty_secrets := Paste_Secrets_Config{github_gist_token = "token", active_key_id = "a"}
	testing.expect(t, paste_secrets_validate(&empty_secrets) == .Invalid_Key_Count)
	invalid_material_configs: [1]Paste_Key_Config
	invalid_material_configs[0] = {id = "a", key_hex = "00"}
	invalid_material := Paste_Secrets_Config{
		github_gist_token = "token", active_key_id = "a", keys = invalid_material_configs[:],
	}
	testing.expect(t, paste_secrets_validate(&invalid_material) == .Invalid_Key_Material)
	missing_active_configs: [1]Paste_Key_Config
	missing_active_configs[0] = {id = "a", key_hex = material_a}
	missing_active := Paste_Secrets_Config{
		github_gist_token = "token", active_key_id = "missing", keys = missing_active_configs[:],
	}
	testing.expect(t, paste_secrets_validate(&missing_active) == .Missing_Active_Key)
	empty_token := Paste_Secrets_Config{
		github_gist_token = "", active_key_id = "a", keys = missing_active_configs[:],
	}
	testing.expect(t, paste_secrets_validate(&empty_token) == .Empty_Token)
	invalid_id_configs: [1]Paste_Key_Config
	invalid_id_configs[0] = {id = "not valid", key_hex = material_a}
	invalid_id := Paste_Secrets_Config{
		github_gist_token = "token", active_key_id = "a", keys = invalid_id_configs[:],
	}
	testing.expect(t, paste_secrets_validate(&invalid_id) == .Invalid_Key_Id)
	duplicate_id_configs: [2]Paste_Key_Config
	duplicate_id_configs[0] = {id = "a", key_hex = material_a}
	duplicate_id_configs[1] = {id = "a", key_hex = material_b}
	duplicate_id := Paste_Secrets_Config{
		github_gist_token = "token", active_key_id = "a", keys = duplicate_id_configs[:],
	}
	testing.expect(t, paste_secrets_validate(&duplicate_id) == .Duplicate_Key_Id)
	duplicate_material_configs: [2]Paste_Key_Config
	duplicate_material_configs[0] = {id = "a", key_hex = material_a}
	duplicate_material_configs[1] = {id = "b", key_hex = material_a}
	duplicate_material := Paste_Secrets_Config{
		github_gist_token = "token", active_key_id = "a", keys = duplicate_material_configs[:],
	}
	testing.expect(t, paste_secrets_validate(&duplicate_material) == .Duplicate_Key_Material)

	invalid_keyring: Paste_Keyring
	testing.expect(t, paste_keyring_init(&invalid_keyring, &empty_secrets, allocator) == .Invalid_Key_Count)
	paste_keyring_destroy(&invalid_keyring, allocator)
	invalid_codec: Paste_Codec
	testing.expect(t, paste_codec_init(&invalid_codec, &invalid_keyring) == .Invalid_Input)

	valid_configs: [1]Paste_Key_Config
	valid_configs[0] = {id = "a", key_hex = material_a}
	valid_secrets := Paste_Secrets_Config{
		github_gist_token = "token", active_key_id = "a", keys = valid_configs[:],
	}
	keyring: Paste_Keyring
	keyring_err := paste_keyring_init(&keyring, &valid_secrets, allocator)
	testing.expect(t, keyring_err == .None)
	if keyring_err != .None {
		return
	}
	defer paste_keyring_destroy(&keyring, allocator)
	codec: Paste_Codec
	if paste_codec_init(&codec, &keyring) != .None {
		testing.expect(t, false)
		return
	}
	defer paste_codec_destroy(&codec)

	max_title, max_title_alloc_err := make([]byte, PASTE_TITLE_MAX_BYTES, allocator)
	testing.expect(t, max_title_alloc_err == nil)
	if max_title_alloc_err != nil {
		return
	}
	for &c in max_title {
		c = 'a'
	}
	defer {
		paste_wipe_bytes(max_title)
		delete(max_title, allocator)
	}
	max_envelope, max_pid, max_err := paste_encrypt_new(&codec, string(max_title), "", 0, 4, allocator)
	testing.expect(t, max_err == .None)
	if max_err == .None {
		paste_wipe_string(max_envelope)
		delete(max_envelope, allocator)
		paste_wipe_string(max_pid)
		delete(max_pid, allocator)
	}
	exact_body_envelope, exact_body_pid, exact_body_err := paste_encrypt_new(&codec, "title", "1234", 0, 4, allocator)
	testing.expect(t, exact_body_err == .None)
	if exact_body_err == .None {
		paste_wipe_string(exact_body_envelope)
		delete(exact_body_envelope, allocator)
		paste_wipe_string(exact_body_pid)
		delete(exact_body_pid, allocator)
	}


	over_title, over_title_alloc_err := make([]byte, PASTE_TITLE_MAX_BYTES + 1, allocator)
	testing.expect(t, over_title_alloc_err == nil)
	if over_title_alloc_err != nil {
		return
	}
	for &c in over_title {
		c = 'a'
	}
	defer {
		paste_wipe_bytes(over_title)
		delete(over_title, allocator)
	}
	_, _, over_title_err := paste_encrypt_new(&codec, string(over_title), "", 0, 4, allocator)
	testing.expect(t, over_title_err == .Invalid_Input)
	_, _, empty_title_err := paste_encrypt_new(&codec, "", "", 0, 4, allocator)
	testing.expect(t, empty_title_err == .Invalid_Input)
	_, _, over_body_err := paste_encrypt_new(&codec, "title", "12345", 0, 4, allocator)
	testing.expect(t, over_body_err == .Too_Large)
	_, _, invalid_limit_err := paste_encrypt_new(&codec, "title", "", 0, -1, allocator)
	testing.expect(t, invalid_limit_err == .Invalid_Input)
	invalid_utf8 := [1]byte{0xff}
	_, _, invalid_title_utf8_err := paste_encrypt_new(&codec, string(invalid_utf8[:]), "", 0, 4, allocator)
	testing.expect(t, invalid_title_utf8_err == .Invalid_Input)
	_, _, invalid_body_utf8_err := paste_encrypt_new(&codec, "title", string(invalid_utf8[:]), 0, 4, allocator)
	testing.expect(t, invalid_body_utf8_err == .Invalid_Input)
	_, _, invalid_time_err := paste_encrypt_new(&codec, "title", "", -1, 4, allocator)
	testing.expect(t, invalid_time_err == .Invalid_Input)
}
