// package provides a very simple (for now) HTTP/1.1 client.
package client

import "base:runtime"
import "core:bufio"
import "core:bytes"
import "core:c"
import "core:encoding/json"
import "core:io"
import "core:log"
import "core:mem"
import "core:nbio"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import http ".."
import openssl "../openssl"

Request :: struct {
	method:          http.Method,
	headers:         http.Headers,
	cookies:         [dynamic]http.Cookie,
	body:            bytes.Buffer,
	connect_timeout: time.Duration,
	read_timeout:    time.Duration,
	write_timeout:   time.Duration,
}

DEFAULT_CONNECT_TIMEOUT :: 10 * time.Second
DEFAULT_READ_TIMEOUT    :: 30 * time.Second
DEFAULT_WRITE_TIMEOUT   :: 30 * time.Second

tls_hostname :: proc(authority: string) -> string {
	if len(authority) > 2 && authority[0] == '[' {
		if bracket := strings.index_byte(authority, ']'); bracket > 1 {
			return authority[1:bracket]
		}
	}

	first_colon := strings.index_byte(authority, ':')
	last_colon := strings.last_index_byte(authority, ':')
	if first_colon > 0 && first_colon == last_colon {
		return authority[:first_colon]
	}
	return authority
}

// Initializes the request with sane defaults using the given allocator.
request_init :: proc(r: ^Request, method := http.Method.Get, allocator := context.allocator) {
	r.method = method
	r.connect_timeout = DEFAULT_CONNECT_TIMEOUT
	r.read_timeout = DEFAULT_READ_TIMEOUT
	r.write_timeout = DEFAULT_WRITE_TIMEOUT
	http.headers_init(&r.headers, allocator)
	r.cookies = make([dynamic]http.Cookie, allocator)
	bytes.buffer_init_allocator(&r.body, 0, 0, allocator)
}

// Destroys the request.
// Header keys and values that the user added will have to be deleted by the user.
// Same with any strings inside the cookies.
request_destroy :: proc(r: ^Request) {
	delete(r.headers._kv)
	delete(r.cookies)
	bytes.buffer_destroy(&r.body)
}

with_json :: proc(r: ^Request, v: any, opt: json.Marshal_Options = {}) -> json.Marshal_Error {
	if r.method == .Get { r.method = .Post }
	http.headers_set_content_type(&r.headers, http.mime_to_content_type(.Json))

	stream := bytes.buffer_to_stream(&r.body)
	opt := opt
	json.marshal_to_writer(io.to_writer(stream), v, &opt) or_return
	return nil
}

get :: proc(target: string, allocator := context.allocator) -> (Response, Error) {
	r: Request
	request_init(&r, .Get, allocator)
	defer request_destroy(&r)

	return request(&r, target, allocator)
}

Request_Error :: enum {
	Ok,
	Invalid_Response_HTTP_Version,
	Invalid_Response_Status,
	Invalid_Response_Header,
	Invalid_Response_Cookie,
	Unexpected_Response_EOF,
}

SSL_Error :: enum {
	Ok,
	Context_Init_Failed,
	Trust_Roots_Unavailable,
	SSL_Init_Failed,
	Socket_Association_Failed,
	SNI_Setup_Failed,
	Hostname_Verification_Setup_Failed,
	Handshake_Timed_Out,
	Handshake_Failed,
	Certificate_Verification_Failed,
	SSL_Write_Timed_Out,
	SSL_Write_Failed,
}

Deadline_Operation :: enum {
	Connect,
	Read,
	Write,
}

Deadline_Error :: struct {
	operation: Deadline_Operation,
	cause:     net.Socket_Option_Error,
}

Dial_Job_State :: enum i32 {
	Working,
	Completed,
	Abandoned,
}

Dial_Job :: struct {
	state:     Dial_Job_State,
	target:    string,
	timeout:   time.Duration,
	socket:    net.TCP_Socket,
	socket_owned: bool,
	err:       net.Network_Error,
	allocator: mem.Allocator,
}

dial_job_destroy :: proc(job: ^Dial_Job, close_socket := false) {
	if close_socket && job.socket_owned {
		net.close(job.socket)
	}
	delete(job.target, job.allocator)
	free(job, job.allocator)
}

dial_job_run :: proc(job: ^Dial_Job) {
	_, endpoint, endpoint_err := parse_endpoint(job.target)
	job.err = endpoint_err

	if job.err == nil && sync.atomic_load_explicit(&job.state, .Acquire) == .Working {
		if loop_err := nbio.acquire_thread_event_loop(); loop_err != nil {
			job.err = net.Dial_Error.Unknown
		} else {
			nbio.dial_poly(
				endpoint,
				job,
				proc(op: ^nbio.Operation, job: ^Dial_Job) {
					job.socket = op.dial.socket
					job.socket_owned = op.dial.err == nil
					job.err = op.dial.err
				},
				timeout = job.timeout,
			)
			if loop_err := nbio.run(); loop_err != nil {
				job.err = net.Dial_Error.Unknown
			}
			nbio.release_thread_event_loop()
		}
	}

	_, completed := sync.atomic_compare_exchange_strong_explicit(
		&job.state,
		.Working,
		.Completed,
		.Release,
		.Relaxed,
	)
	if !completed {
		dial_job_destroy(job, close_socket = true)
	}
}

dial_target_with_timeout :: proc(target: string, timeout: time.Duration) -> (socket: net.TCP_Socket, err: net.Network_Error) {
	allocator := runtime.heap_allocator()
	job, allocation_err := new(Dial_Job, allocator)
	if allocation_err != .None {
		return {}, net.Create_Socket_Error.Insufficient_Resources
	}
	job.allocator = allocator
	job.timeout = timeout
	job.target, allocation_err = strings.clone(target, allocator)
	if allocation_err != .None {
		free(job, allocator)
		return {}, net.Create_Socket_Error.Insufficient_Resources
	}

	previous_allocator := context.allocator
	context.allocator = allocator
	dial_thread := thread.create_and_start_with_poly_data(job, dial_job_run, self_cleanup = true)
	context.allocator = previous_allocator
	if dial_thread == nil {
		dial_job_destroy(job)
		return {}, net.Create_Socket_Error.Insufficient_Resources
	}

	deadline := time.time_add(time.now(), timeout)
	for {
		state := sync.atomic_load_explicit(&job.state, .Acquire)
		if state == .Completed {
			socket, err = job.socket, job.err
			if err != nil && job.socket_owned {
				net.close(socket)
			}
			dial_job_destroy(job)
			if err == nil {
				if blocking_err := net.set_blocking(socket, true); blocking_err != nil {
					net.close(socket)
					return {}, net.Dial_Error.Unknown
				}
			}
			return
		}

		if time.diff(time.now(), deadline) <= 0 {
			_, abandoned := sync.atomic_compare_exchange_strong_explicit(
				&job.state,
				.Working,
				.Abandoned,
				.Acq_Rel,
				.Acquire,
			)
			if abandoned {
				return {}, net.Dial_Error.Timeout
			}
			continue
		}
		time.sleep(time.Millisecond)
	}
}

Error :: union {
	net.Dial_Error,
	net.Parse_Endpoint_Error,
	net.Network_Error,
	net.TCP_Send_Error,
	bufio.Scanner_Error,
	Request_Error,
	SSL_Error,
	Deadline_Error,
}

request :: proc(request: ^Request, target: string, allocator := context.allocator) -> (res: Response, err: Error) {
	url := http.url_parse(target)
	connect_timeout := request.connect_timeout if request.connect_timeout > 0 else DEFAULT_CONNECT_TIMEOUT
	read_timeout := request.read_timeout if request.read_timeout > 0 else DEFAULT_READ_TIMEOUT
	write_timeout := request.write_timeout if request.write_timeout > 0 else DEFAULT_WRITE_TIMEOUT

	// NOTE: we don't support persistent connections yet.
	http.headers_set_close(&request.headers)

	req_buf := format_request(url, request, allocator)
	defer bytes.buffer_destroy(&req_buf)

	socket, dial_err := dial_target_with_timeout(target, connect_timeout)
	if dial_err != nil {
		err = dial_err
		return
	}
	socket_owned := true
	defer if socket_owned { net.close(socket) }

	// The connect timeout also bounds the TLS handshake. Once connected, use the
	// operation-specific deadlines for all subsequent network I/O.
	if option_err := net.set_option(socket, .Receive_Timeout, connect_timeout); option_err != nil {
		err = Deadline_Error{operation = .Connect, cause = option_err}
		return
	}
	if option_err := net.set_option(socket, .Send_Timeout, connect_timeout); option_err != nil {
		err = Deadline_Error{operation = .Connect, cause = option_err}
		return
	}

	// HTTPS using OpenSSL.
	if url.scheme == "https" {
		ctx := openssl.SSL_CTX_new(openssl.TLS_client_method())
		if ctx == nil {
			err = SSL_Error.Context_Init_Failed
			return
		}
		ssl := cast(^openssl.SSL)(nil)
		tls_owned := true
		defer if tls_owned {
			if ssl != nil { openssl.SSL_free(ssl) }
			openssl.SSL_CTX_free(ctx)
		}

		if openssl.SSL_CTX_set_default_verify_paths(ctx) != 1 {
			err = SSL_Error.Trust_Roots_Unavailable
			return
		}
		openssl.SSL_CTX_set_verify(ctx, openssl.SSL_VERIFY_PEER, nil)

		ssl = openssl.SSL_new(ctx)
		if ssl == nil {
			err = SSL_Error.SSL_Init_Failed
			return
		}
		if openssl.SSL_set_fd(ssl, c.int(socket)) != 1 {
			err = SSL_Error.Socket_Association_Failed
			return
		}

		// Set SNI for DNS names and independently enforce the certificate identity.
		hostname := tls_hostname(url.host)
		chostname := strings.clone_to_cstring(hostname, allocator)
		defer delete(chostname, allocator)
		_, is_ip4 := net.parse_ip4_address(hostname)
		_, is_ip6 := net.parse_ip6_address(hostname)
		if !is_ip4 && !is_ip6 && openssl.SSL_set_tlsext_host_name(ssl, chostname) != 1 {
			err = SSL_Error.SNI_Setup_Failed
			return
		}
		identity_ok := openssl.X509_VERIFY_PARAM_set1_ip_asc(openssl.SSL_get0_param(ssl), chostname) if is_ip4 || is_ip6 else openssl.SSL_set1_host(ssl, chostname)
		if identity_ok != 1 {
			err = SSL_Error.Hostname_Verification_Setup_Failed
			return
		}

		connect_result := openssl.SSL_connect(ssl)
		if connect_result != 1 {
			ssl_error := openssl.SSL_get_error(ssl, connect_result)
			err = SSL_Error.Handshake_Timed_Out if ssl_error == 2 || ssl_error == 3 else SSL_Error.Handshake_Failed
			return
		}
		if openssl.SSL_get_verify_result(ssl) != openssl.X509_V_OK {
			err = SSL_Error.Certificate_Verification_Failed
			return
		}

		if option_err := net.set_option(socket, .Receive_Timeout, read_timeout); option_err != nil {
			err = Deadline_Error{operation = .Read, cause = option_err}
			return
		}
		if option_err := net.set_option(socket, .Send_Timeout, write_timeout); option_err != nil {
			err = Deadline_Error{operation = .Write, cause = option_err}
			return
		}

		buf := bytes.buffer_to_bytes(&req_buf)
		written := 0
		for written < len(buf) {
			ret := openssl.SSL_write(ssl, raw_data(buf[written:]), c.int(len(buf) - written))
			if ret <= 0 {
				ssl_error := openssl.SSL_get_error(ssl, ret)
				err = SSL_Error.SSL_Write_Timed_Out if ssl_error == 2 || ssl_error == 3 else SSL_Error.SSL_Write_Failed
				return
			}
			written += int(ret)
		}

		res, err = parse_response(SSL_Communication{ssl = ssl, ctx = ctx, socket = socket}, allocator)
		if err == nil {
			tls_owned = false
			socket_owned = false
		}
		return
	}

	if option_err := net.set_option(socket, .Receive_Timeout, read_timeout); option_err != nil {
		err = Deadline_Error{operation = .Read, cause = option_err}
		return
	}
	if option_err := net.set_option(socket, .Send_Timeout, write_timeout); option_err != nil {
		err = Deadline_Error{operation = .Write, cause = option_err}
		return
	}

	// HTTP, just send the request.
	net.send_tcp(socket, bytes.buffer_to_bytes(&req_buf)) or_return
	res, err = parse_response(socket, allocator)
	if err == nil { socket_owned = false }
	return
}

Response :: struct {
	status:    http.Status,
	// headers and cookies should be considered read-only, after a response is returned.
	headers:   http.Headers,
	cookies:   [dynamic]http.Cookie,
	_socket:   Communication,
	_body:     bufio.Scanner,
	_body_err: Body_Error,
}

// Frees the response, closes the connection.
// Optionally pass the response_body returned 'body' and 'was_allocation' to destroy it too.
response_destroy :: proc(res: ^Response, body: Maybe(Body_Type) = nil, was_allocation := false, body_allocator := context.allocator) {
	// Header keys are allocated, values are slices into the body.
	// NOTE: this is fine because we don't add any headers with `headers_set_unsafe()`.
	// If we did, we wouldn't know if the key was allocated or a literal.
	// We also set the headers to readonly before giving them to the user so they can't add any either.
	for k, v in res.headers._kv {
		delete(v, res.headers._kv.allocator)
		delete(k, res.headers._kv.allocator)
	}

	delete(res.headers._kv)

	bufio.scanner_destroy(&res._body)

	for cookie in res.cookies {
		delete(cookie._raw, res.cookies.allocator)
	}
	delete(res.cookies)

	if body != nil {
		body_destroy(body.(Body_Type), was_allocation, body_allocator)
	}

	// We close now and not at the time we got the response because reading the body,
	// could make more reads need to happen (like with chunked encoding).
	switch comm in res._socket {
	case net.TCP_Socket:
		net.close(comm)
	case SSL_Communication:
		openssl.SSL_free(comm.ssl)
		openssl.SSL_CTX_free(comm.ctx)
		net.close(comm.socket)
	}
}

Body_Error :: enum {
	None,
	No_Length,
	Invalid_Length,
	Too_Long,
	Scan_Failed,
	Invalid_Chunk_Size,
	Invalid_Trailer_Header,
}

// Any non-special body, could have been a chunked body that has been read in fully automatically.
// Depending on the return value for 'was_allocation' of the parse function, this is either an
// allocated string that you should delete or a slice into the body.
Body_Plain :: string

// A URL encoded body, map, keys and values are fully allocated on the allocator given to the parsing function,
// And should be deleted by you.
Body_Url_Encoded :: map[string]string

Body_Type :: union #no_nil {
	Body_Plain,
	Body_Url_Encoded,
	Body_Error, // TODO: why is this here if we also return an error?
}

// Frees the memory allocated by parsing the body.
// was_allocation is returned by the body parsing procedure.
body_destroy :: proc(body: Body_Type, was_allocation: bool, allocator := context.allocator) {
	switch b in body {
	case Body_Plain:
		if was_allocation { delete(b, allocator) }
	case Body_Url_Encoded:
		for k, v in b {
			delete(k, b.allocator)
			delete(v, b.allocator)
		}
		delete(b)
	case Body_Error:
	}
}

// Retrieves the response's body, can only be called once.
// Free the returned body using body_destroy().
response_body :: proc(
	res: ^Response,
	max_length := -1,
	allocator := context.allocator,
) -> (
	body: Body_Type,
	was_allocation: bool,
	err: Body_Error,
) {
	defer res._body_err = err
	assert(res._body_err == nil)
	body, was_allocation, err = _parse_body(&res.headers, &res._body, max_length, allocator)
	return
}

_parse_body :: proc(
	headers: ^http.Headers,
	_body: ^bufio.Scanner,
	max_length := -1,
	allocator := context.allocator,
) -> (
	body: Body_Type,
	was_allocation: bool,
	err: Body_Error,
) {
	// See [RFC 7230 3.3.3](https://www.rfc-editor.org/rfc/rfc7230#section-3.3.3) for the rules.
	// Point 3 paragraph 3 and point 4 are handled before we get here.

	enc, has_enc       := http.headers_get_unsafe(headers^, "transfer-encoding")
	length, has_length := http.headers_get_unsafe(headers^, "content-length")
	switch {
	case has_enc && strings.has_suffix(enc, "chunked"):
		was_allocation = true
		body = _response_body_chunked(headers, _body, max_length, allocator) or_return

	case has_length:
		body = _response_body_length(_body, max_length, length) or_return

	case:
		body = _response_till_close(_body, max_length) or_return
	}

	// Automatically decode url encoded bodies.
	if typ, ok := http.headers_get_unsafe(headers^, "content-type"); ok && typ == "application/x-www-form-urlencoded" {
		plain := body.(Body_Plain)
		defer if was_allocation { delete(plain, allocator) }

		keyvalues := strings.split(plain, "&", allocator)
		defer delete(keyvalues, allocator)

		queries := make(Body_Url_Encoded, len(keyvalues), allocator)
		for keyvalue in keyvalues {
			seperator := strings.index(keyvalue, "=")
			if seperator == -1 { 	// The keyvalue has no value.
				queries[keyvalue] = ""
				continue
			}

			key, key_decoded_ok := net.percent_decode(keyvalue[:seperator], allocator)
			if !key_decoded_ok {
				log.warnf("url encoded body key %q could not be decoded", keyvalue[:seperator])
				continue
			}

			val, val_decoded_ok := net.percent_decode(keyvalue[seperator + 1:], allocator)
			if !val_decoded_ok {
				log.warnf("url encoded body value %q for key %q could not be decoded", keyvalue[seperator + 1:], key)
				continue
			}

			queries[key] = val
		}

		body = queries
	}

	return
}

_response_till_close :: proc(_body: ^bufio.Scanner, max_length: int) -> (string, Body_Error) {
	_body.max_token_size = max_length
	defer _body.max_token_size = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE

	_body.split = proc(data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool) {
		if at_eof {
			return len(data), data, nil, true
		}

		return
	}
	defer _body.split = bufio.scan_lines

	if !bufio.scanner_scan(_body) {
		if bufio.scanner_error(_body) == .Too_Long {
			return "", .Too_Long
		}

		return "", .Scan_Failed
	}

	return bufio.scanner_text(_body), .None
}

// "Decodes" a response body based on the content length header.
// Meant for internal usage, you should use `client.response_body`.
_response_body_length :: proc(_body: ^bufio.Scanner, max_length: int, len: string) -> (string, Body_Error) {
	ilen, lenok := strconv.parse_int(len, 10)
	if !lenok || ilen < 0 {
		return "", .Invalid_Length
	}

	if max_length > -1 && ilen > max_length {
		return "", .Too_Long
	}

	if ilen == 0 {
		return "", nil
	}

	// user_index is used to set the amount of bytes to scan in scan_num_bytes.
	context.user_index = ilen

	_body.max_token_size = ilen
	defer _body.max_token_size = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE

	_body.split = scan_num_bytes
	defer _body.split = bufio.scan_lines

	log.debugf("scanning %i bytes body", ilen)

	if !bufio.scanner_scan(_body) {
		return "", .Scan_Failed
	}

	return bufio.scanner_text(_body), .None
}

// "Decodes" a chunked transfer encoded request body.
// Meant for internal usage, you should use `client.response_body`.
//
// RFC 7230 4.1.3 pseudo-code:
//
// length := 0
// read chunk-size, chunk-ext (if any), and CRLF
// while (chunk-size > 0) {
//    read chunk-data and CRLF
//    append chunk-data to decoded-body
//    length := length + chunk-size
//    read chunk-size, chunk-ext (if any), and CRLF
// }
// read trailer field
// while (trailer field is not empty) {
//    if (trailer field is allowed to be sent in a trailer) {
//    	append trailer field to existing header fields
//    }
//    read trailer-field
// }
// Content-Length := length
// Remove "chunked" from Transfer-Encoding
// Remove Trailer from existing header fields
_response_body_chunked :: proc(
	headers: ^http.Headers,
	_body: ^bufio.Scanner,
	max_length: int,
	allocator := context.allocator,
) -> (
	body: string,
	err: Body_Error,
) {
	body_buff: bytes.Buffer

	bytes.buffer_init_allocator(&body_buff, 0, 0, allocator)
	defer if err != nil { bytes.buffer_destroy(&body_buff) }

	for {
		if !bufio.scanner_scan(_body) {
			return "", .Scan_Failed
		}

		size_line := bufio.scanner_bytes(_body)

		// If there is a semicolon, discard everything after it,
		// that would be chunk extensions which we currently have no interest in.
		if semi := bytes.index_byte(size_line, ';'); semi > -1 {
			size_line = size_line[:semi]
		}

		size, ok := strconv.parse_int(string(size_line), 16)
		if !ok || size < 0 {
			err = .Invalid_Chunk_Size
			return
		}
		if size == 0 { break }

		if max_length > -1 && bytes.buffer_length(&body_buff) + size > max_length {
			return "", .Too_Long
		}

		// user_index is used to set the amount of bytes to scan in scan_num_bytes.
		context.user_index = size

		_body.max_token_size = size
		_body.split = scan_num_bytes

		if !bufio.scanner_scan(_body) {
			return "", .Scan_Failed
		}

		_body.max_token_size = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE
		_body.split = bufio.scan_lines

		bytes.buffer_write(&body_buff, bufio.scanner_bytes(_body))

		// Read empty line after chunk.
		if !bufio.scanner_scan(_body) || bufio.scanner_text(_body) != "" {
			return "", .Scan_Failed
		}
	}

	// Read trailing empty line (after body, before trailing headers).
	if !bufio.scanner_scan(_body) || bufio.scanner_text(_body) != "" {
		return "", .Scan_Failed
	}

	// Keep parsing the request as line delimited headers until we get to an empty line.
	for {
		// If there are no trailing headers, this case is hit.
		if !bufio.scanner_scan(_body) {
			break
		}

		line := bufio.scanner_text(_body)

		// The first empty line denotes the end of the headers section.
		if line == "" {
			break
		}

		key, ok := http.header_parse(headers, line)
		if !ok {
			return "", .Invalid_Trailer_Header
		}

		// A recipient MUST ignore (or consider as an error) any fields that are forbidden to be sent in a trailer.
		if !http.header_allowed_trailer(key) {
			http.headers_delete(headers, key)
		}
	}

	if http.headers_has_unsafe(headers^, "trailer") {
		http.headers_delete_unsafe(headers, "trailer")
	}

	te := strings.trim_suffix(http.headers_get_unsafe(headers^, "transfer-encoding"), "chunked")

	headers.readonly = false
	http.headers_set_unsafe(headers, "transfer-encoding", te)
	headers.readonly = true

	return bytes.buffer_to_string(&body_buff), .None
}

// A scanner bufio.Split_Proc implementation to scan a given amount of bytes.
// The amount of bytes should be set in the context.user_index.
@(private)
scan_num_bytes :: proc(
	data: []byte,
	at_eof: bool,
) -> (
	advance: int,
	token: []byte,
	err: bufio.Scanner_Error,
	final_token: bool,
) {
	n := context.user_index // Set context.user_index to the amount of bytes to read.
	if at_eof && len(data) < n {
		return
	}

	if len(data) < n {
		return
	}

	return n, data[:n], nil, false
}
