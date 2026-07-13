package main

import "core:bufio"
import "core:crypto"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"

import http "lib:odin-http"
import http_client "lib:odin-http/client"

GIST_API_VERSION               :: "2022-11-28"
GIST_USER_AGENT                :: "sacha.house-paste/1.0"
GIST_BEARER_PREFIX             :: "Bearer "
GIST_DEFAULT_MAX_RESPONSE_BYTES :: 4 * 1024 * 1024
GIST_ERROR_BODY_MAX_BYTES      :: 16 * 1024
GIST_MAX_RETRY_AFTER_SECONDS   :: 24 * 60 * 60
GIST_MAX_ID_BYTES              :: 64

Gist_Client :: struct {
	base_url:           string,
	bearer_token:       []byte,
	api_version:        string,
	max_response_bytes: int,
	allocator:          mem.Allocator,
}

Gist_File :: struct {
	filename:  string,
	raw_url:   string,
	content:   string,
	size:      int,
	truncated: bool,
}

Gist_History :: struct {
	version:      string,
	committed_at: string,
}

Gist :: struct {
	id:          string,
	description: string,
	created_at:  string,
	updated_at:  string,
	public:      bool,
	files:       map[string]Gist_File,
	history:     []Gist_History,
}

Gist_Write_File :: struct {
	content: string,
}

Gist_Create_Request :: struct {
	description: string,
	public:      bool,
	files:       map[string]Gist_Write_File,
}

Gist_Update_Request :: struct {
	files: map[string]Gist_Write_File,
}

Gist_Error_Kind :: enum {
	None,
	Network,
	Timeout,
	TLS,
	Unauthorized,
	Forbidden,
	Not_Found,
	Rate_Limited,
	Validation,
	Response_Too_Large,
	Malformed_Response,
	Upstream,
	Outcome_Unknown,
}

Gist_Error :: struct {
	kind:                Gist_Error_Kind,
	status:              http.Status,
	retry_after_seconds: int,
	message:             string,
}

gist_client_init :: proc(
	client: ^Gist_Client,
	base_url: string,
	token: []byte,
	allocator: mem.Allocator,
) -> Gist_Error {
	if client == nil || allocator.procedure == nil || !gist_base_url_valid(base_url) || !gist_token_valid(token) {
		return {
			kind = .Validation,
			message = "invalid GitHub Gist client configuration",
		}
	}
	if client.base_url != "" || client.bearer_token != nil {
		return {
			kind = .Validation,
			message = "GitHub Gist client is already initialized",
		}
	}

	normalized_url := strings.trim_right(base_url, "/")
	owned_url, url_alloc_err := strings.clone(normalized_url, allocator)
	if url_alloc_err != .None {
		return {
			kind = .Upstream,
			message = "could not initialize GitHub Gist client",
		}
	}

	owned_token, token_alloc_err := make([]byte, len(token), allocator)
	if token_alloc_err != .None {
		delete(owned_url, allocator)
		return {
			kind = .Upstream,
			message = "could not initialize GitHub Gist client",
		}
	}
	copy(owned_token, token)

	client^ = Gist_Client {
		base_url           = owned_url,
		bearer_token       = owned_token,
		api_version        = GIST_API_VERSION,
		max_response_bytes = GIST_DEFAULT_MAX_RESPONSE_BYTES,
		allocator          = allocator,
	}
	return {}
}

gist_client_destroy :: proc(client: ^Gist_Client) {
	if client == nil {
		return
	}
	if len(client.bearer_token) > 0 {
		crypto.zero_explicit(raw_data(client.bearer_token), len(client.bearer_token))
		delete(client.bearer_token, client.allocator)
	}
	if client.base_url != "" {
		delete(client.base_url, client.allocator)
	}
	client^ = {}
}

gist_list :: proc(
	client: ^Gist_Client,
	page, per_page: int,
	allocator := context.temp_allocator,
) -> ([]Gist, Gist_Error) {
	if page < 1 || per_page < 1 || per_page > 100 {
		return nil, {
			kind = .Validation,
			message = "invalid GitHub Gist page request",
		}
	}
	if !gist_client_ready(client) {
		return nil, {
			kind = .Validation,
			message = "GitHub Gist client is not initialized",
		}
	}

	target := fmt.tprintf("%s/gists?per_page=%d&page=%d", client.base_url, per_page, page)
	gists: []Gist
	err := gist_request_json(client, .Get, target, nil, .OK, false, &gists, allocator)
	if err.kind != .None {
		return nil, err
	}
	return gists, {}
}

gist_get :: proc(
	client: ^Gist_Client,
	id: string,
	allocator := context.temp_allocator,
) -> (Gist, Gist_Error) {
	if !gist_id_valid(id) {
		return {}, {
			kind = .Validation,
			message = "invalid GitHub Gist identifier",
		}
	}
	if !gist_client_ready(client) {
		return {}, {
			kind = .Validation,
			message = "GitHub Gist client is not initialized",
		}
	}

	target := fmt.tprintf("%s/gists/%s", client.base_url, id)
	gist: Gist
	err := gist_request_json(client, .Get, target, nil, .OK, false, &gist, allocator)
	if err.kind != .None {
		return {}, err
	}
	return gist, {}
}

gist_create :: proc(
	client: ^Gist_Client,
	input: ^Gist_Create_Request,
	allocator := context.temp_allocator,
) -> (Gist, Gist_Error) {
	if input == nil {
		return {}, {
			kind = .Validation,
			message = "invalid GitHub Gist create request",
		}
	}
	if !gist_client_ready(client) {
		return {}, {
			kind = .Validation,
			message = "GitHub Gist client is not initialized",
		}
	}

	target := fmt.tprintf("%s/gists", client.base_url)
	gist: Gist
	err := gist_request_json(client, .Post, target, input, .Created, true, &gist, allocator)
	if err.kind != .None {
		return {}, err
	}
	return gist, {}
}

gist_update :: proc(
	client: ^Gist_Client,
	id: string,
	input: ^Gist_Update_Request,
	allocator := context.temp_allocator,
) -> (Gist, Gist_Error) {
	if !gist_id_valid(id) || input == nil {
		return {}, {
			kind = .Validation,
			message = "invalid GitHub Gist update request",
		}
	}
	if !gist_client_ready(client) {
		return {}, {
			kind = .Validation,
			message = "GitHub Gist client is not initialized",
		}
	}

	target := fmt.tprintf("%s/gists/%s", client.base_url, id)
	gist: Gist
	err := gist_request_json(client, .Patch, target, input, .OK, true, &gist, allocator)
	if err.kind != .None {
		return {}, err
	}
	return gist, {}
}

gist_delete :: proc(client: ^Gist_Client, id: string) -> Gist_Error {
	if !gist_id_valid(id) {
		return {
			kind = .Validation,
			message = "invalid GitHub Gist identifier",
		}
	}
	if !gist_client_ready(client) {
		return {
			kind = .Validation,
			message = "GitHub Gist client is not initialized",
		}
	}

	target := fmt.tprintf("%s/gists/%s", client.base_url, id)
	return gist_request_json(client, .Delete, target, nil, .No_Content, true, nil, context.temp_allocator)
}

@(private)
gist_request_json :: proc(
	gist_client: ^Gist_Client,
	method: http.Method,
	target: string,
	payload: any,
	expected_status: http.Status,
	mutation: bool,
	output: any,
	allocator: mem.Allocator,
) -> Gist_Error {
	if !gist_client_ready(gist_client) {
		return {
			kind = .Validation,
			message = "GitHub Gist client is not initialized",
		}
	}

	request: http_client.Request
	http_client.request_init(&request, method, context.temp_allocator)
	defer http_client.request_destroy(&request)

	authorization, auth_alloc_err := make(
		[]byte,
		len(GIST_BEARER_PREFIX) + len(gist_client.bearer_token),
		context.temp_allocator,
	)
	if auth_alloc_err != .None {
		return {
			kind = .Upstream,
			message = "could not prepare GitHub request",
		}
	}
	copy(authorization[:len(GIST_BEARER_PREFIX)], GIST_BEARER_PREFIX)
	copy(authorization[len(GIST_BEARER_PREFIX):], gist_client.bearer_token)
	defer {
		crypto.zero_explicit(raw_data(authorization), len(authorization))
		delete(authorization, context.temp_allocator)
	}

	http.headers_set_unsafe(&request.headers, "accept", "application/vnd.github+json")
	http.headers_set_unsafe(&request.headers, "authorization", string(authorization))
	http.headers_set_unsafe(&request.headers, "x-github-api-version", gist_client.api_version)
	http.headers_set_unsafe(&request.headers, "user-agent", GIST_USER_AGENT)

	if payload != nil {
		if marshal_err := http_client.with_json(&request, payload); marshal_err != nil {
			return {
				kind = .Validation,
				message = "could not encode GitHub Gist request",
			}
		}
	}

	response, request_err := http_client.request(&request, target, context.temp_allocator)
	if request_err != nil {
		return gist_transport_error(request_err, mutation)
	}

	if response.status != expected_status {
		err := gist_status_error(&response)
		gist_discard_response(&response, GIST_ERROR_BODY_MAX_BYTES)
		return err
	}

	if output == nil {
		gist_discard_response(&response, 0)
		return {}
	}

	body, was_allocation, body_err := http_client.response_body(
		&response,
		gist_client.max_response_bytes,
		context.temp_allocator,
	)
	if body_err != .None {
		http_client.response_destroy(&response)
		return gist_body_error(body_err, response.status, mutation)
	}
	defer http_client.response_destroy(
		&response,
		body,
		was_allocation,
		context.temp_allocator,
	)

	body_text: string
	switch value in body {
	case http_client.Body_Plain:
		body_text = string(value)
	case http_client.Body_Url_Encoded:
		return {
			kind = .Malformed_Response,
			status = response.status,
			message = "GitHub returned an unsupported response body",
		}
	case http_client.Body_Error:
		return gist_body_error(value, response.status, mutation)
	}

	if unmarshal_err := json.unmarshal_any(transmute([]byte)body_text, output, allocator = allocator); unmarshal_err != nil {
		return {
			kind = .Malformed_Response,
			status = response.status,
			message = "GitHub returned malformed JSON",
		}
	}
	return {}
}

@(private)
gist_discard_response :: proc(response: ^http_client.Response, max_bytes: int) {
	body, was_allocation, body_err := http_client.response_body(
		response,
		max_bytes,
		context.temp_allocator,
	)
	if body_err == .None {
		http_client.response_destroy(
			response,
			body,
			was_allocation,
			context.temp_allocator,
		)
		return
	}
	http_client.response_destroy(response)
}

@(private)
gist_status_error :: proc(response: ^http_client.Response) -> Gist_Error {
	status := response.status
	switch status {
	case .Unauthorized:
		return {
			kind = .Unauthorized,
			status = status,
			message = "GitHub authentication was rejected",
		}
	case .Forbidden:
		if gist_rate_limit_exhausted(response) {
			return {
				kind = .Rate_Limited,
				status = status,
				retry_after_seconds = gist_retry_after_seconds(response),
				message = "GitHub rate limit is exhausted",
			}
		}
		return {
			kind = .Forbidden,
			status = status,
			message = "GitHub denied the Gist request",
		}
	case .Not_Found:
		return {
			kind = .Not_Found,
			status = status,
			message = "GitHub Gist was not found",
		}
	case .Request_Timeout:
		return {
			kind = .Timeout,
			status = status,
			message = "GitHub request timed out",
		}
	case .Unprocessable_Content:
		return {
			kind = .Validation,
			status = status,
			message = "GitHub rejected the Gist request",
		}
	case .Too_Many_Requests:
		return {
			kind = .Rate_Limited,
			status = status,
			retry_after_seconds = gist_retry_after_seconds(response),
			message = "GitHub rate limit is exhausted",
		}
	case .Continue, .Switching_Protocols, .Processing, .Early_Hints,
	     .OK, .Created, .Accepted, .Non_Authoritative_Information, .No_Content,
	     .Reset_Content, .Partial_Content, .Multi_Status, .Already_Reported, .IM_Used,
	     .Multiple_Choices, .Moved_Permanently, .Found, .See_Other, .Not_Modified,
	     .Use_Proxy, .Unused, .Temporary_Redirect, .Permanent_Redirect,
	     .Bad_Request, .Payment_Required, .Method_Not_Allowed, .Not_Acceptable,
	     .Proxy_Authentication_Required, .Conflict, .Gone, .Length_Required,
	     .Precondition_Failed, .Payload_Too_Large, .URI_Too_Long,
	     .Unsupported_Media_Type, .Range_Not_Satisfiable, .Expectation_Failed,
	     .Im_A_Teapot, .Misdirected_Request, .Locked, .Failed_Dependency, .Too_Early,
	     .Upgrade_Required, .Precondition_Required, .Request_Header_Fields_Too_Large,
	     .Unavailable_For_Legal_Reasons, .Internal_Server_Error, .Not_Implemented,
	     .Bad_Gateway, .Service_Unavailable, .Gateway_Timeout,
	     .HTTP_Version_Not_Supported, .Variant_Also_Negotiates,
	     .Insufficient_Storage, .Loop_Detected, .Not_Extended,
	     .Network_Authentication_Required:
		return {
			kind = .Upstream,
			status = status,
			message = "GitHub returned an unexpected status",
		}
	}
	return {kind = .Upstream, status = status, message = "GitHub returned an unexpected status"}
}

@(private)
gist_transport_error :: proc(err: http_client.Error, mutation: bool) -> Gist_Error {
	switch specific in err {
	case http_client.SSL_Error:
		 switch specific {
		case .Handshake_Timed_Out:
			return {
				kind = .Timeout,
				message = "GitHub TLS handshake timed out",
			}
		case .SSL_Write_Timed_Out, .SSL_Write_Failed:
			if mutation {
				return {
					kind = .Outcome_Unknown,
					message = "GitHub mutation outcome is unknown",
				}
			}
			if specific == .SSL_Write_Timed_Out {
				return {
					kind = .Timeout,
					message = "GitHub request timed out",
				}
			}
			return {
				kind = .TLS,
				message = "GitHub TLS transport failed",
			}
		case .Ok, .Context_Init_Failed, .Trust_Roots_Unavailable, .SSL_Init_Failed,
		     .Socket_Association_Failed, .SNI_Setup_Failed,
		     .Hostname_Verification_Setup_Failed, .Handshake_Failed,
		     .Certificate_Verification_Failed:
			return {
				kind = .TLS,
				message = "GitHub TLS verification or handshake failed",
			}
		}
	case net.Dial_Error:
		if specific == .Timeout {
			return {
				kind = .Timeout,
				message = "GitHub connection timed out",
			}
		}
		return {
			kind = .Network,
			message = "GitHub connection failed",
		}
	case net.TCP_Send_Error:
		if mutation {
			return {
				kind = .Outcome_Unknown,
				message = "GitHub mutation outcome is unknown",
			}
		}
		if specific == .Timeout {
			return {
				kind = .Timeout,
				message = "GitHub request timed out",
			}
		}
		return {
			kind = .Network,
			message = "GitHub request could not be sent",
		}
	case http_client.Request_Error, bufio.Scanner_Error:
		if mutation {
			return {
				kind = .Outcome_Unknown,
				message = "GitHub mutation outcome is unknown",
			}
		}
		return {
			kind = .Upstream,
			message = "GitHub returned a malformed response",
		}
	case http_client.Deadline_Error, net.Parse_Endpoint_Error:
		return {
			kind = .Network,
			message = "GitHub connection setup failed",
		}
	case net.Network_Error:
		 switch network_err in specific {
		case net.Dial_Error:
			if network_err == .Timeout {
				return {
					kind = .Timeout,
					message = "GitHub connection timed out",
				}
			}
		case net.Create_Socket_Error, net.Listen_Error, net.Accept_Error, net.Bind_Error,
		     net.TCP_Send_Error, net.UDP_Send_Error, net.TCP_Recv_Error, net.UDP_Recv_Error,
		     net.Shutdown_Error, net.Interfaces_Error, net.Socket_Info_Error,
		     net.Socket_Option_Error, net.Set_Blocking_Error, net.Parse_Endpoint_Error,
		     net.Resolve_Error, net.DNS_Error:
		case nil:
		}
		return {
			kind = .Network,
			message = "GitHub network request failed",
		}
	case:
		if mutation {
			return {
				kind = .Outcome_Unknown,
				message = "GitHub mutation outcome is unknown",
			}
		}
		return {
			kind = .Network,
			message = "GitHub network request failed",
		}
	}
	return {kind = .Outcome_Unknown if mutation else .Network, message = "GitHub transport failed"}
}

@(private)
gist_body_error :: proc(
	body_err: http_client.Body_Error,
	status: http.Status,
	mutation: bool,
) -> Gist_Error {
	switch body_err {
	case .Too_Long:
		return {
			kind = .Response_Too_Large,
			status = status,
			message = "GitHub response exceeded the configured limit",
		}
	case .Scan_Failed:
		if mutation {
			return {
				kind = .Outcome_Unknown,
				status = status,
				message = "GitHub mutation outcome is unknown",
			}
		}
		return {
			kind = .Network,
			status = status,
			message = "GitHub response could not be read",
		}
	case .None, .No_Length, .Invalid_Length, .Invalid_Chunk_Size, .Invalid_Trailer_Header:
		return {
			kind = .Malformed_Response,
			status = status,
			message = "GitHub returned an invalid response body",
		}
	}
	return {kind = .Malformed_Response, status = status, message = "GitHub returned an invalid response body"}
}

@(private)
gist_rate_limit_exhausted :: proc(response: ^http_client.Response) -> bool {
	if remaining, present := http.headers_get_unsafe(response.headers, "x-ratelimit-remaining"); present {
		if value, ok := strconv.parse_i64(remaining, 10); ok && value == 0 {
			return true
		}
	}
	if retry_after, present := http.headers_get_unsafe(response.headers, "retry-after"); present {
		seconds, ok := strconv.parse_i64(retry_after, 10)
		return ok && seconds >= 0
	}
	return false
}

@(private)
gist_retry_after_seconds :: proc(response: ^http_client.Response) -> int {
	if value, present := http.headers_get_unsafe(response.headers, "retry-after"); present {
		if seconds, ok := strconv.parse_i64(value, 10); ok {
			return gist_bound_retry_after(seconds)
		}
	}

	if value, present := http.headers_get_unsafe(response.headers, "x-ratelimit-reset"); present {
		if reset_at, ok := strconv.parse_i64(value, 10); ok {
			now := time.to_unix_seconds(time.now())
			return gist_bound_retry_after(reset_at - now)
		}
	}
	return 0
}

@(private)
gist_bound_retry_after :: proc(seconds: i64) -> int {
	if seconds <= 0 {
		return 0
	}
	if seconds > GIST_MAX_RETRY_AFTER_SECONDS {
		return GIST_MAX_RETRY_AFTER_SECONDS
	}
	return int(seconds)
}

@(private)
gist_client_ready :: proc(client: ^Gist_Client) -> bool {
	return client != nil &&
		client.base_url != "" &&
		len(client.bearer_token) > 0 &&
		client.api_version == GIST_API_VERSION &&
		client.max_response_bytes > 0
}

@(private)
gist_base_url_valid :: proc(base_url: string) -> bool {
	if base_url == "" || strings.index_byte(base_url, '?') >= 0 || strings.index_byte(base_url, '#') >= 0 {
		return false
	}
	for byte in transmute([]byte)base_url {
		if byte <= ' ' || byte == 0x7f {
			return false
		}
	}

	url := http.url_parse(base_url)
	return url.scheme == "https" &&
		url.host != "" &&
		strings.index_byte(url.host, '@') < 0
}

@(private)
gist_token_valid :: proc(token: []byte) -> bool {
	if len(token) == 0 {
		return false
	}
	for byte in token {
		if byte <= ' ' || byte == 0x7f {
			return false
		}
	}
	return true
}

@(private)
gist_id_valid :: proc(id: string) -> bool {
	if len(id) < 1 || len(id) > GIST_MAX_ID_BYTES {
		return false
	}
	for byte in transmute([]byte)id {
		switch byte {
		case '0'..='9', 'a'..='f', 'A'..='F':
		case:
			return false
		}
	}
	return true
}
