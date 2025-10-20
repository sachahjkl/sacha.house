package main

import "core:encoding/json"
import "core:fmt"
import "core:log"

import client "lib:odin-http/client"
import http "lib:odin-http"

with_bearer_auth :: proc(req: ^client.Request, token: string) {
	http.headers_set(&req.headers, "Authorization", fmt.tprintf("Bearer %s", token))
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
		msg := fmt.tprintf("GraphQL request failed: %s", req_err)
		log.error(msg)
		return nil, Error{type = .Network, msg = msg}
	}
	defer client.response_destroy(&client_res)

	res_body, allocation, body_err := client.response_body(&client_res)
	if body_err != nil {
		msg := fmt.tprintf("Error retrieving response body: %s", body_err)
		log.error(msg)
		return nil, Error{type = .Network, msg = msg}
	}
	defer client.body_destroy(res_body, allocation)

	body_bytes, ok := res_body.(client.Body_Plain)
	if !ok {
		msg := "Error converting body to bytes"
		log.error(msg)
		return nil, Error{type = .Validation, msg = msg}
	}

	// Clone the response body since it will be deallocated after this procedure returns.
	// (temp allocator because the values are only used for the duration of the request)
	cloned_body := make([]u8, len(body_bytes), context.temp_allocator)
	copy(cloned_body, body_bytes[:])

	return cloned_body, Error{type = .None}
}
