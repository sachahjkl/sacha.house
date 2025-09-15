package main

import "core:mem/virtual"
import "core:time"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

import http "odin-http"
import client "odin-http/client"


GitLab_Project :: struct {
	name:            string,
	url:             string,
	avatarUrl:       string,
	description:     string,
	descriptionHtml: string,
	visibility:      string,
}

GitLab_Projects_Response :: struct {
	data: struct {
		projects: struct {
			nodes: []GitLab_Project,
		},
	},
}

GitHub_Project :: struct {
	name:            string,
	url:             string,
	description:     string,
	descriptionHtml: string,
	visibility:      string,
	owner:           struct {
		avatarUrl: string,
	},
}

GitHub_Projects_Response :: struct {
	data: struct {
		user: struct {
			projects: struct {
				nodes: []GitHub_Project,
			},
		},
	},
}

gitlab_projects_api :: proc() -> (projects: []GitLab_Project, err: Error) {
	gitlab_token := APP_CONFIG.GITLAB_BEARER_TOKEN
	if gitlab_token == "" {
		msg := "GITLAB_BEARER_TOKEN is not set"
		return nil, Error{type = .Authorization, msg = msg}
	}

	req_body: GraphQL_Request
	req_body.query =
	`
		query GET_PROJECTS_GITLAB {
			projects(membership: true) {
				nodes {
					name
					url: webUrl
					avatarUrl
					description
					descriptionHtml
					visibility
				}
			}
		}
	`


	req_body.variables = make(map[string]string, context.temp_allocator)
	req_body.variables["username"] = ME.username

	body_bytes, req_err := graphql_request(APP_CONFIG.GITLAB_API_ENDPOINT, gitlab_token, req_body)
	if req_err.type != .None {
		return nil, req_err
	}

	projects_res: GitLab_Projects_Response
	unmarshal_err := json.unmarshal(body_bytes, &projects_res, allocator = context.temp_allocator)
	if unmarshal_err != nil {
		msg := fmt.tprintf("Error unmarshalling gitlab projects: %s", unmarshal_err)
		log.error(msg)
		return nil, Error{type = .JSON_Unmarshal, msg = msg}
	}

	public_projects := make(
		[dynamic]GitLab_Project,
		0,
		len(projects_res.data.projects.nodes),
		context.temp_allocator,
	)
	for project in projects_res.data.projects.nodes {
		if strings.to_lower(project.visibility, context.temp_allocator) != "private" {
			append(&public_projects, project)
		}
	}

	// NOTE(sachahjkl):
	// the public_projects slice is only used for the duration of the request, so we use the temp allocator.
	// This means the caller doesn't need to clean it up since the temp allocator is cleaned up at the end of the request
	return public_projects[:], Error{type = .None}
}

github_projects_api :: proc() -> (projects: []GitHub_Project, err: Error) {
	github_token := APP_CONFIG.GITHUB_BEARER_TOKEN
	if github_token == "" {
		msg := "GITHUB_BEARER_TOKEN is not set"
		return nil, Error{type = .Authorization, msg = msg}
	}

	req_body: GraphQL_Request
	req_body.query =
	`
		query GET_PROJECTS_GITHUB($username: String!) {
			user(login: $username) {
				projects: repositories(first: 50) {
					nodes {
						name
						url
						description
						descriptionHTML
						visibility
						owner {
							avatarUrl
						}
					}
				}
			}
		}
	`


	req_body.variables = make(map[string]string, context.temp_allocator)
	req_body.variables["username"] = ME.username

	body_bytes, req_err := graphql_request(
		APP_CONFIG.GITHUB_GRAPHQL_API_ENDPOINT,
		github_token,
		req_body,
	)
	if req_err.type != .None {
		return nil, req_err
	}

	projects_res: GitHub_Projects_Response
	unmarshal_err := json.unmarshal(body_bytes, &projects_res, allocator = context.temp_allocator)
	if unmarshal_err != nil {
		msg := fmt.tprintf("Error unmarshalling github projects: %s", unmarshal_err)
		log.error(msg)
		return nil, Error{type = .JSON_Unmarshal, msg = msg}
	}

	public_projects := make(
		[dynamic]GitHub_Project,
		0,
		len(projects_res.data.user.projects.nodes),
		context.temp_allocator,
	)
	for project in projects_res.data.user.projects.nodes {
		if strings.to_lower(project.visibility, context.temp_allocator) != "private" {
			append(&public_projects, project)
		}
	}

	// NOTE(sachahjkl):
	// the public_projects slice is only used for the duration of the request, so we use the temp allocator.
	// This means the caller doesn't need to clean it up since the temp allocator is cleaned up at the end of the request
	return public_projects[:], Error{type = .None}
}
