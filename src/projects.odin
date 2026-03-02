package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:strings"

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

Standardized_Project :: struct {
	name:            string,
	url:             string,
	descriptionHtml: string,
	avatarUrl:       string,
	first_letter:    string,
	hslColor:        string,
	hasAvatar:       bool,
}

gitlab_projects_api :: proc() -> (projects: []GitLab_Project, err: Error) {
	gitlab_token := APP_CONFIG.GITLAB_BEARER_TOKEN
	if gitlab_token == "" {
		msg := "GITLAB_BEARER_TOKEN is not set"
		return nil, Error{type = .Authorization, msg = msg}
	}

	req_body: GraphQL_Request
	req_body.query = `
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
	req_body.query = `
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


fetch_projects :: proc(use_cache := true) -> ^Projects_Cache {

	if use_cache && projects_cache.status == .Filled {
		log.info("Serving projects from cache.")
		return &projects_cache
	}

	log.info("Fetching fresh projects, cache empty.")
	reset_project_cache()

	gitlab_projects_raw, gitlab_err := gitlab_projects_api()
	if gitlab_err.type != .None {
		log.errorf("could not get gitlab projects: %v", gitlab_err)
		return nil
	}

	log.info("Fetched gitlab projects.")

	github_projects_raw, github_err := github_projects_api()
	if github_err.type != .None {
		log.errorf("could not get github projects: %v", github_err)
		return nil
	}

	log.info("Fetched github projects.")

	projects_cache.gitlab = make(
		[]Standardized_Project,
		len(gitlab_projects_raw),
		projects_cache.allocator,
	)

	for project, i in gitlab_projects_raw {
		first_letter :=
			strings.to_upper(project.name[:1], projects_cache.allocator) if len(project.name) > 0 else ""
		projects_cache.gitlab[i] = Standardized_Project {
			name            = strings.clone(project.name, projects_cache.allocator),
			url             = strings.clone(project.url, projects_cache.allocator),
			descriptionHtml = strings.clone(project.descriptionHtml, projects_cache.allocator),
			avatarUrl       = strings.clone(project.avatarUrl, projects_cache.allocator),
			first_letter    = first_letter,
			hslColor        = generate_random_hsl_string(projects_cache.allocator),
			hasAvatar       = strings.clone(project.avatarUrl, projects_cache.allocator) != "",
		}
	}

	// NOTE(sachahjkl):
	// use the context.allocator instead of context.temp_allocator here
	// because the values are cached and will be used later
	projects_cache.github = make(
		[]Standardized_Project,
		len(github_projects_raw),
		projects_cache.allocator,
	)
	for project, i in github_projects_raw {
		first_letter :=
			strings.to_upper(project.name[:1], projects_cache.allocator) if len(project.name) > 0 else ""
		projects_cache.github[i] = Standardized_Project {
			name            = strings.clone(project.name, projects_cache.allocator),
			url             = strings.clone(project.url, projects_cache.allocator),
			descriptionHtml = strings.clone(project.descriptionHtml, projects_cache.allocator),
			avatarUrl       = strings.clone(project.owner.avatarUrl, projects_cache.allocator),
			first_letter    = first_letter,
			hslColor        = generate_random_hsl_string(projects_cache.allocator),
			hasAvatar       = strings.clone(
				project.owner.avatarUrl,
				projects_cache.allocator,
			) != "",
		}
	}
	projects_cache.status = .Filled

	log.info("Filled projects cache.")

	dump_projects_cache(PROJECTS_CACHE_FILE)

	return &projects_cache
}


get_project_cache_status :: proc() -> Project_Cache_Status {
	return projects_cache.status
}

// Cache for the projects

Project_Cache_Status :: enum {
	Unitialized,
	Empty,
	Filled,
}


Projects_Cache :: struct {
	status:    Project_Cache_Status,
	gitlab:    []Standardized_Project,
	github:    []Standardized_Project,
	arena:     virtual.Arena,
	allocator: mem.Allocator,
}


projects_cache: Projects_Cache

PROJECTS_CACHE_FILE :: "projects_cache.json"

Projects_Cache_Serializable :: struct {
	gitlab: []Standardized_Project,
	github: []Standardized_Project,
}

dump_projects_cache :: proc(path: string) -> bool {
	if projects_cache.status != .Filled {
		log.warn("Cannot dump projects cache: not filled")
		return false
	}

	cache_data := Projects_Cache_Serializable {
		gitlab = projects_cache.gitlab,
		github = projects_cache.github,
	}

	json_bytes, marshal_err := json.marshal(cache_data, {pretty = true}, context.temp_allocator)
	if marshal_err != nil {
		log.errorf("Failed to marshal projects cache: %v", marshal_err)
		return false
	}

	if err := os.write_entire_file_from_bytes(path, json_bytes); err != os.ERROR_NONE {
		log.errorf("Failed to write projects cache to %s", path)
		return false
	}

	log.infof("Projects cache dumped to %s", path)
	return true
}

restore_projects_cache :: proc(path: string) -> bool {
	json_bytes, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != os.ERROR_NONE {
		log.errorf("Failed to read projects cache from %s", path)
		return false
	}

	cache_data: Projects_Cache_Serializable
	unmarshal_err := json.unmarshal(json_bytes, &cache_data, allocator = projects_cache.allocator)
	if unmarshal_err != nil {
		log.errorf("Failed to unmarshal projects cache: %v", unmarshal_err)
		return false
	}

	projects_cache.gitlab = cache_data.gitlab
	projects_cache.github = cache_data.github
	projects_cache.status = .Filled

	log.infof("Projects cache restored from %s", path)
	return true
}

init_projects_cache :: proc() -> mem.Allocator_Error {

	if (projects_cache.status != .Unitialized) {
		log.warn("Projects cache already initialized")
		return .None
	}

	virtual.arena_init_growing(&projects_cache.arena) or_return
	projects_cache.allocator = virtual.arena_allocator(&projects_cache.arena)
	projects_cache.status = .Empty
	log.info("Projects cache initialized")

	return .None
}


reset_project_cache :: proc() {
	virtual.arena_free_all(&projects_cache.arena)
	projects_cache.status = .Empty
}

cleanup_projects_cache :: proc() {
	virtual.arena_destroy(&projects_cache.arena)
	projects_cache.status = .Unitialized
}

first_load_projects_cache :: proc() -> mem.Allocator_Error {
	log.info("Initializing projects cache.")
	if err := init_projects_cache(); err != .None {
		log.error("Could not initialize projects cache.")
		return err
	}

	if os.exists(PROJECTS_CACHE_FILE) {
		log.info("Found cached projects file, loading from disk")
		if restore_projects_cache(PROJECTS_CACHE_FILE) {
			return .None
		}
		log.warn("Failed to restore cache from disk, will fetch fresh")
	}

	fetch_projects(use_cache = false)
	return .None
}
