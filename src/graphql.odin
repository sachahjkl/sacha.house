package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:strings"

import client "lib:odin-http/client"
import http "lib:odin-http"

GRAPHQL_MAX_RESPONSE_BYTES :: 4 * 1024 * 1024

GraphQL_Response_Metadata :: struct {
	errors: []struct {
		message: string,
	},
}

with_bearer_auth :: proc(req: ^client.Request, token: string) {
	http.headers_set_unsafe(&req.headers, "authorization", strings.concatenate([]string{"Bearer ", token}, context.temp_allocator))
}

// NOTE(sachahjkl):
// the response body is only used for the duration of the request, so we use the temp allocator.
// This means the caller doesn't need to clean it up since the temp allocator is cleaned up at the end of the request
graphql_request :: proc(endpoint, token: string, body: GraphQL_Request) -> (response_body: []u8, err: Error) {
	client_req: client.Request
	client.request_init(&client_req, .Post)
	defer client.request_destroy(&client_req)

	with_bearer_auth(&client_req, token)

	if json_err := client.with_json(&client_req, body); json_err != nil {
		msg := fmt.tprintf("JSON marshal error: %s", json_err)
		log.error(msg)
		return nil, Error{type = .JSON_Marshal, msg = msg}
	}

	client_res, req_err := client.request(&client_req, endpoint)
	if req_err != nil {
		msg := fmt.tprintf("GraphQL transport failed: %s", req_err)
		log.error(msg)
		return nil, Error{type = .Network, msg = msg}
	}
	defer client.response_destroy(&client_res)

	if !http.status_is_success(client_res.status) {
		msg := fmt.tprintf("GraphQL API returned HTTP status %d", int(client_res.status))
		log.error(msg)
		return nil, Error{type = .HTTP_Status, msg = msg, status = int(client_res.status)}
	}

	res_body, allocation, body_err := client.response_body(
		&client_res,
		max_length = GRAPHQL_MAX_RESPONSE_BYTES,
	)
	if body_err != nil {
		msg := fmt.tprintf("Error retrieving GraphQL response body: %s", body_err)
		log.error(msg)
		return nil, Error{type = .Network, msg = msg}
	}
	defer client.body_destroy(res_body, allocation)

	body_bytes, ok := res_body.(client.Body_Plain)
	if !ok {
		msg := "GraphQL API returned an unsupported response body"
		log.error(msg)
		return nil, Error{type = .Validation, msg = msg}
	}

	metadata: GraphQL_Response_Metadata
	if metadata_err := json.unmarshal(transmute([]u8)body_bytes, &metadata, allocator = context.temp_allocator); metadata_err != nil {
		msg := fmt.tprintf("Error unmarshalling GraphQL response metadata: %s", metadata_err)
		log.error(msg)
		return nil, Error{type = .JSON_Unmarshal, msg = msg}
	}
	if len(metadata.errors) > 0 {
		msg := fmt.tprintf("GraphQL API returned %d error(s)", len(metadata.errors))
		log.error(msg)
		return nil, Error{type = .GraphQL, msg = msg}
	}

	// Clone the response body since it will be deallocated after this procedure returns.
	// (temp allocator because the values are only used for the duration of the request)
	cloned_body := make([]u8, len(body_bytes), context.temp_allocator)
	copy(cloned_body, body_bytes[:])

	return cloned_body, Error{type = .None}
}
