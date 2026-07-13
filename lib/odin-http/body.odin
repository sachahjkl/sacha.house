package http

import "core:bufio"
import "core:io"
import "core:strconv"
import "core:strings"
import "core:mem/virtual"
import "core:testing"
 
@(test)
test_form_url_encoded_decodes_plus_and_percent_escapes :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	testing.expect(t, arena_err == .None)
	if arena_err != .None do return
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	form, ok := body_url_encoded(
		"paste%2Btitle=hello+world%21%2B&path=%2Fadmin%2Fpastes",
		allocator,
	)
	testing.expect(t, ok)
	if !ok do return

	title, title_exists := form["paste+title"]
	testing.expect(t, title_exists)
	testing.expect(t, title == "hello world!+")
	path, path_exists := form["path"]
	testing.expect(t, path_exists)
	testing.expect(t, path == "/admin/pastes")
}

@(test)
test_form_url_encoded_rejects_malformed_percent_escapes :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	testing.expect(t, arena_err == .None)
	if arena_err != .None do return
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	malformed := []Body {
		"%", "%2", "%GG", "%0g", "key=%", "key=%2", "key=%GG",
	}
	for value in malformed {
		_, ok := body_url_encoded(value, allocator)
		testing.expect(t, !ok)
	}
}

@(test)
test_content_length_helper_requires_only_decimal_digits :: proc(t: ^testing.T) {
	valid := []string {"0", "1", "00042", "18446744073709551616"}
	for value in valid {
		testing.expect(t, _content_length_valid(value))
	}

	invalid := []string {"", "-1", "+1", " 1", "1 ", "1,2", "1x", "0x10"}
	for value in invalid {
		testing.expect(t, !_content_length_valid(value))
	}
}

@(test)
test_body_length_rejects_invalid_and_overflow_values_without_reading :: proc(t: ^testing.T) {
	State :: struct {
		called: bool,
		err:    Body_Error,
	}
	on_body :: proc(user_data: rawptr, _: Body, err: Body_Error) {
		state := (^State)(user_data)
		state.called = true
		state.err = err
	}

	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	testing.expect(t, arena_err == .None)
	if arena_err != .None do return
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	invalid := []string {
		"", "-1", "+1", " 1", "1 ", "1,2", "0x10", "18446744073709551616",
	}
	for value in invalid {
		req: Request
		request_init(&req, allocator)
		headers_set_unsafe(&req.headers, "content-length", value)
		state: State
		_body_length(&req, -1, &state, on_body)
		testing.expect(t, state.called)
		testing.expect(t, body_error_status(state.err) == .Bad_Request)
	}
}

Body :: string

Body_Callback :: #type proc(user_data: rawptr, body: Body, err: Body_Error)

Body_Error :: bufio.Scanner_Error

/*
Retrieves the request's body.

If the request has the chunked Transfer-Encoding header set, the chunks are all read and returned.
Otherwise, the Content-Length header is used to determine what to read and return it.

`max_length` can be used to set a maximum amount of bytes we try to read, once it goes over this,
an error is returned.

Do not call this more than once.

**Tip** If an error is returned, easily respond with an appropriate error code like this, `http.respond(res, http.body_error_status(err))`.
*/
body :: proc(req: ^Request, max_length: int = -1, user_data: rawptr, cb: Body_Callback) {
	assert(req._body_ok == nil, "you can only call body once per request")

	enc_header, ok := headers_get_unsafe(req.headers, "transfer-encoding")
	if ok && strings.has_suffix(enc_header, "chunked") {
		_body_chunked(req, max_length, user_data, cb)
	} else {
		_body_length(req, max_length, user_data, cb)
	}
}

/*
Parses a URL encoded body, aka bodies with the 'Content-Type: application/x-www-form-urlencoded'.

Key&value pairs are percent decoded and put in a map.
*/
_form_hex_nibble :: #force_inline proc(c: byte) -> (byte, bool) {
	switch c {
	case '0'..='9': return c - '0', true
	case 'a'..='f': return c - 'a' + 10, true
	case 'A'..='F': return c - 'A' + 10, true
	case:          return 0, false
	}
}

_form_decode_component :: proc(value: string, allocator := context.temp_allocator) -> (decoded: string, ok: bool) {
	needs_decoding := false
	for c in value {
		if c == '+' || c == '%' {
			needs_decoding = true
			break
		}
	}
	if !needs_decoding { return value, true }

	b := strings.builder_make(0, len(value), allocator)
	for i := 0; i < len(value); i += 1 {
		switch value[i] {
		case '+':
			strings.write_byte(&b, ' ')
		case '%':
			if i + 2 >= len(value) { return "", false }
			hi, hi_ok := _form_hex_nibble(value[i + 1])
			lo, lo_ok := _form_hex_nibble(value[i + 2])
			if !hi_ok || !lo_ok { return "", false }
			strings.write_byte(&b, hi << 4 | lo)
			i += 2
		case:
			strings.write_byte(&b, value[i])
		}
	}

	return strings.to_string(b), true
}

body_url_encoded :: proc(plain: Body, allocator := context.temp_allocator) -> (res: map[string]string, ok: bool) {

	insert :: proc(m: ^map[string]string, plain: string, keys: int, vals: int, end: int, allocator := context.temp_allocator) -> bool {
		has_value := vals != -1
		key_end   := vals - 1 if has_value else end
		key       := plain[keys:key_end]
		val       := plain[vals:end] if has_value else ""

		key_decoded := _form_decode_component(key, allocator) or_return
		val_decoded := ""
		if has_value {
			val_decoded = _form_decode_component(val, allocator) or_return
		}

		m[key_decoded] = val_decoded
		return true
	}

	count := 1
	for b in plain {
		if b == '&' { count += 1 }
	}

	queries := make(map[string]string, count, allocator)

	keys := 0
	vals := -1
	for b, i in plain {
		switch b {
		case '=':
			if vals == -1 { vals = i + 1 }
		case '&':
			insert(&queries, plain, keys, vals, i) or_return
			keys = i + 1
			vals = -1
		}
	}

	insert(&queries, plain, keys, vals, len(plain)) or_return

	return queries, true
}

// Returns an appropriate status code for the given body error.
body_error_status :: proc(e: Body_Error) -> Status {
	switch t in e {
	case bufio.Scanner_Extra_Error:
		switch t {
		case .Too_Long:                            return .Payload_Too_Large
		case .Too_Short, .Bad_Read_Count:          return .Bad_Request
		case .Negative_Advance, .Advanced_Too_Far: return .Internal_Server_Error
		case .None:                                return .OK
		case:
			return .Internal_Server_Error
		}
	case io.Error:
		switch t {
		case .EOF, .Unknown, .No_Progress, .Unexpected_EOF:
			return .Bad_Request
		case .Empty, .Short_Write, .Buffer_Full, .Short_Buffer,
		     .Invalid_Write, .Negative_Read, .Invalid_Whence, .Invalid_Offset,
		     .Invalid_Unread, .Negative_Write, .Negative_Count,
		     .Permission_Denied, .No_Size, .Closed:
			return .Internal_Server_Error
		case .None:
			return .OK
		case:
			return .Internal_Server_Error
		}
	case: unreachable()
	}
}


// "Decodes" a request body based on the content length header.
// Meant for internal usage, you should use `http.request_body`.
_body_length :: proc(req: ^Request, max_length: int = -1, user_data: rawptr, cb: Body_Callback) {
	req._body_ok = false

	content_length, ok := headers_get_unsafe(req.headers, "content-length")
	if !ok {
		cb(user_data, "", nil)
		return
	}

	if len(content_length) == 0 {
		cb(user_data, "", .Bad_Read_Count)
		return
	}
	for c in content_length {
		if c < '0' || c > '9' {
			cb(user_data, "", .Bad_Read_Count)
			return
		}
	}

	ilen := 0
	for c in content_length {
		digit := int(c - '0')
		if ilen > (max(int) - digit) / 10 {
			cb(user_data, "", .Bad_Read_Count)
			return
		}
		ilen = ilen * 10 + digit
	}

	if max_length > -1 && ilen > max_length {
		cb(user_data, "", .Too_Long)
		return
	}

	if ilen == 0 {
		req._body_ok = true
		cb(user_data, "", nil)
		return
	}

	req._scanner.max_token_size = ilen

	req._scanner.split          = scan_num_bytes
	req._scanner.split_data     = rawptr(uintptr(ilen))

	req._body_ok = true
	scanner_scan(req._scanner, user_data, cb)
}

/*
"Decodes" a chunked transfer encoded request body.
Meant for internal usage, you should use `http.request_body`.

PERF: this could be made non-allocating by writing over the part of the body that contains the
metadata with the rest of the body, and then returning a slice of that, but it is some effort and
I don't think this functionality of HTTP is used that much anyway.

RFC 7230 4.1.3 pseudo-code:

length := 0
read chunk-size, chunk-ext (if any), and CRLF
while (chunk-size > 0) {
   read chunk-data and CRLF
   append chunk-data to decoded-body
   length := length + chunk-size
   read chunk-size, chunk-ext (if any), and CRLF
}
read trailer field
while (trailer field is not empty) {
   if (trailer field is allowed to be sent in a trailer) {
   	append trailer field to existing header fields
   }
   read trailer-field
}
Content-Length := length
Remove "chunked" from Transfer-Encoding
Remove Trailer from existing header fields
*/
_scan_crlf_line :: proc(split_data: rawptr, data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool) {
	for c, i in data {
		if c != '\n' { continue }
		if i == 0 || data[i - 1] != '\r' {
			return 0, nil, .Bad_Read_Count, false
		}
		return i + 1, data[:i - 1], nil, false
	}

	if at_eof {
		return 0, nil, .Unexpected_EOF, false
	}
	return
}

_body_chunked :: proc(req: ^Request, max_length: int = -1, user_data: rawptr, cb: Body_Callback) {
	req._body_ok = false

	on_scan :: proc(s: rawptr, size_line: string, err: bufio.Scanner_Error) {
		s := cast(^Chunked_State)s
		size_line := size_line

		if err != nil {
			s.cb(s.user_data, "", err)
			return
		}

		// If there is a semicolon, discard everything after it,
		// that would be chunk extensions which we currently have no interest in.
		if semi := strings.index_byte(size_line, ';'); semi > -1 {
			size_line = size_line[:semi]
		}

		if len(size_line) == 0 {
			s.cb(s.user_data, "", .Bad_Read_Count)
			return
		}
		for c in size_line {
			if _, valid := _form_hex_nibble(byte(c)); !valid {
				s.cb(s.user_data, "", .Bad_Read_Count)
				return
			}
		}
		size, ok := strconv.parse_int(string(size_line), 16)
		if !ok || size < 0 {
			s.cb(s.user_data, "", .Bad_Read_Count)
			return
		}

		// start scanning trailer headers.
		if size == 0 {
			scanner_scan(s.req._scanner, s, on_scan_trailer)
			return
		}

		if s.max_length > -1 && size > s.max_length - strings.builder_len(s.buf) {
			s.cb(s.user_data, "", .Too_Long)
			return
		}

		s.req._scanner.max_token_size = size

		s.req._scanner.split          = scan_num_bytes
		s.req._scanner.split_data     = rawptr(uintptr(size))

		scanner_scan(s.req._scanner, s, on_scan_chunk)
	}

	on_scan_chunk :: proc(s: rawptr, token: string, err: bufio.Scanner_Error) {
		s := cast(^Chunked_State)s

		if err != nil {
			s.cb(s.user_data, "", err)
			return
		}

		s.req._scanner.max_token_size = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE
		s.req._scanner.split          = _scan_crlf_line
		strings.write_string(&s.buf, token)

		on_scan_empty_line :: proc(s: rawptr, token: string, err: bufio.Scanner_Error) {
			s := cast(^Chunked_State)s

			if err != nil {
				s.cb(s.user_data, "", err)
				return
			}
			if len(token) != 0 {
				s.cb(s.user_data, "", .Bad_Read_Count)
				return
			}
			scanner_scan(s.req._scanner, s, on_scan)
		}

		scanner_scan(s.req._scanner, s, on_scan_empty_line)
	}

	on_scan_trailer :: proc(s: rawptr, line: string, err: bufio.Scanner_Error) {
		s := cast(^Chunked_State)s

		if err != nil {
			s.cb(s.user_data, "", err)
			return
		}

		// Headers are done, success.
		if len(line) == 0 {
			headers_delete_unsafe(&s.req.headers, "trailer")

			te_header := headers_get_unsafe(s.req.headers, "transfer-encoding")
			new_te_header := strings.trim_suffix(te_header, "chunked")

			s.req.headers.readonly = false
			headers_set_unsafe(&s.req.headers, "transfer-encoding", new_te_header)
			s.req.headers.readonly = true

			s.req._body_ok = true
			s.cb(s.user_data, strings.to_string(s.buf), nil)
			return
		}

		s.req.headers.readonly = false
		key, ok := header_parse(&s.req.headers, string(line))
		s.req.headers.readonly = true
		if !ok {
			s.cb(s.user_data, "", .Unknown)
			return
		}

		// A recipient MUST ignore (or consider as an error) any fields that are forbidden to be sent in a trailer.
		if !header_allowed_trailer(key) {
			headers_delete(&s.req.headers, key)
		}

		scanner_scan(s.req._scanner, s, on_scan_trailer)
	}

	Chunked_State :: struct {
		req:        ^Request,
		max_length: int,
		user_data:  rawptr,
		cb:         Body_Callback,

		buf:        strings.Builder,
	}

	s := new(Chunked_State, context.temp_allocator)

	s.buf.buf.allocator = context.temp_allocator

	s.req        = req
	s.max_length = max_length
	s.user_data  = user_data
	s.cb         = cb

	s.req._scanner.split = _scan_crlf_line
	scanner_scan(s.req._scanner, s, on_scan)
}
