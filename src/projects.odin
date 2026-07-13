package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:math/rand"
import "core:os"
import "core:strings"
import "core:sync"

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

gitlab_projects_api :: proc(config: ^Config, me: ^Me_Info) -> (projects: []GitLab_Project, err: Error) {
	gitlab_token := config.GITLAB_BEARER_TOKEN
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
	req_body.variables["username"] = me.username

	body_bytes, req_err := graphql_request(config.GITLAB_API_ENDPOINT, gitlab_token, req_body)
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
		if !strings.equal_fold(project.visibility, "private") {
			append(&public_projects, project)
		}
	}

	// NOTE(sachahjkl):
	// the public_projects slice is only used for the duration of the request, so we use the temp allocator.
	// This means the caller doesn't need to clean it up since the temp allocator is cleaned up at the end of the request
	return public_projects[:], Error{type = .None}
}

github_projects_api :: proc(config: ^Config, me: ^Me_Info) -> (projects: []GitHub_Project, err: Error) {
	github_token := config.GITHUB_BEARER_TOKEN
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
						descriptionHtml: descriptionHTML
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
	req_body.variables["username"] = me.username

	body_bytes, req_err := graphql_request(
		config.GITHUB_GRAPHQL_API_ENDPOINT,
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
		if !strings.equal_fold(project.visibility, "private") {
			append(&public_projects, project)
		}
	}

	// NOTE(sachahjkl):
	// the public_projects slice is only used for the duration of the request, so we use the temp allocator.
	// This means the caller doesn't need to clean it up since the temp allocator is cleaned up at the end of the request
	return public_projects[:], Error{type = .None}
}


fetch_projects :: proc(state: ^Projects_State, config: ^Config, me: ^Me_Info, use_cache := true) -> (Projects_Cache_Serializable, Error) {
	if use_cache {
		if cached, ok := snapshot_projects_cache(state, context.temp_allocator); ok {
			log.info("Serving projects from cache.")
			return cached, Error{type = .None}
		}
	}

	refresh_err := refresh_projects_cache(state, config, me)
	if refresh_err.type != .None {
		if cached, ok := snapshot_projects_cache(state, context.temp_allocator); ok {
			return cached, refresh_err
		}

		msg := fmt.tprintf(
			"Project refresh failed and no cached projects are available: %s",
			refresh_err.msg,
		)
		return Projects_Cache_Serializable{}, Error{type = refresh_err.type, msg = msg, status = refresh_err.status}
	}

	if cached, ok := snapshot_projects_cache(state, context.temp_allocator); ok {
		return cached, Error{type = .None}
	}

	msg := "Project refresh completed without producing a usable cache"
	return Projects_Cache_Serializable{}, Error{type = .Unknown, msg = msg}
}

refresh_projects_cache :: proc(state: ^Projects_State, config: ^Config, me: ^Me_Info) -> Error {
	sync.lock(&state.refresh_mu)
	defer sync.unlock(&state.refresh_mu)

	log.info("Fetching fresh projects.")
	gitlab_projects_raw, gitlab_err := gitlab_projects_api(config, me)
	if gitlab_err.type != .None {
		log.errorf("Could not get GitLab projects: %s", gitlab_err.msg)
		return gitlab_err
	}

	github_projects_raw, github_err := github_projects_api(config, me)
	if github_err.type != .None {
		log.errorf("Could not get GitHub projects: %s", github_err.msg)
		return github_err
	}

	fresh_cache, allocation_err := new(Projects_Cache, state.allocator)
	if allocation_err != .None {
		msg := "Could not allocate storage for the refreshed project cache"
		log.error(msg)
		return Error{type = .Unknown, msg = msg}
	}
	if arena_err := virtual.arena_init_growing(&fresh_cache.arena); arena_err != .None {
		free(fresh_cache, state.allocator)
		msg := "Could not allocate storage for the refreshed project cache"
		log.error(msg)
		return Error{type = .Unknown, msg = msg}
	}
	committed := false
	defer if !committed {
		virtual.arena_destroy(&fresh_cache.arena)
		free(fresh_cache, state.allocator)
	}
	fresh_cache.allocator = virtual.arena_allocator(&fresh_cache.arena)
	fresh_cache.status = .Filled

	fresh_cache.gitlab = make(
		[]Standardized_Project,
		len(gitlab_projects_raw),
		fresh_cache.allocator,
	)
	for project, i in gitlab_projects_raw {
		first_letter := strings.to_upper(project.name[:1], fresh_cache.allocator) if len(project.name) > 0 else ""
		fresh_cache.gitlab[i] = Standardized_Project {
			name            = strings.clone(project.name, fresh_cache.allocator),
			url             = strings.clone(project.url, fresh_cache.allocator),
			descriptionHtml = strings.clone(project.descriptionHtml, fresh_cache.allocator),
			avatarUrl       = strings.clone(project.avatarUrl, fresh_cache.allocator),
			first_letter    = first_letter,
			hslColor        = generate_random_hsl_string(state.random_generator^, fresh_cache.allocator),
			hasAvatar       = project.avatarUrl != "",
		}
	}

	fresh_cache.github = make(
		[]Standardized_Project,
		len(github_projects_raw),
		fresh_cache.allocator,
	)
	for project, i in github_projects_raw {
		display_index := len(github_projects_raw) - 1 - i
		first_letter := strings.to_upper(project.name[:1], fresh_cache.allocator) if len(project.name) > 0 else ""
		fresh_cache.github[display_index] = Standardized_Project {
			name            = strings.clone(project.name, fresh_cache.allocator),
			url             = strings.clone(project.url, fresh_cache.allocator),
			descriptionHtml = strings.clone(project.descriptionHtml, fresh_cache.allocator),
			avatarUrl       = strings.clone(project.owner.avatarUrl, fresh_cache.allocator),
			first_letter    = first_letter,
			hslColor        = generate_random_hsl_string(state.random_generator^, fresh_cache.allocator),
			hasAvatar       = project.owner.avatarUrl != "",
		}
	}

	sync.lock(&state.cache_mu)
	old_cache := state.cache
	state.cache = fresh_cache
	committed = true
	sync.unlock(&state.cache_mu)

	if old_cache != nil {
		virtual.arena_destroy(&old_cache.arena)
		free(old_cache, state.allocator)
	}

	log.info("Filled projects cache.")
	dump_projects_cache(state, PROJECTS_CACHE_FILE)
	return Error{type = .None}
}

clone_standardized_projects :: proc(projects: []Standardized_Project, allocator: mem.Allocator) -> []Standardized_Project {
	cloned := make([]Standardized_Project, len(projects), allocator)
	for project, i in projects {
		cloned[i] = Standardized_Project {
			name            = strings.clone(project.name, allocator),
			url             = strings.clone(project.url, allocator),
			descriptionHtml = strings.clone(project.descriptionHtml, allocator),
			avatarUrl       = strings.clone(project.avatarUrl, allocator),
			first_letter    = strings.clone(project.first_letter, allocator),
			hslColor        = strings.clone(project.hslColor, allocator),
			hasAvatar       = project.hasAvatar,
		}
	}
	return cloned
}

snapshot_projects_cache :: proc(state: ^Projects_State, allocator: mem.Allocator) -> (Projects_Cache_Serializable, bool) {
	sync.lock(&state.cache_mu)
	defer sync.unlock(&state.cache_mu)
	if state.cache == nil || state.cache.status != .Filled {
		return Projects_Cache_Serializable{}, false
	}
	return Projects_Cache_Serializable {
		gitlab = clone_standardized_projects(state.cache.gitlab, allocator),
		github = clone_standardized_projects(state.cache.github, allocator),
	}, true
}


get_project_cache_status :: proc(state: ^Projects_State) -> Project_Cache_Status {
	sync.lock(&state.cache_mu)
	defer sync.unlock(&state.cache_mu)
	return state.cache.status if state.cache != nil else .Unitialized
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


Projects_State :: struct {
	cache:      ^Projects_Cache,
	cache_mu:   sync.Mutex,
	refresh_mu: sync.Mutex,
	allocator:  mem.Allocator,
	random_generator: ^rand.Generator,
}

PROJECTS_CACHE_FILE :: "projects_cache.json"

Projects_Cache_Serializable :: struct {
	gitlab: []Standardized_Project,
	github: []Standardized_Project,
}

dump_projects_cache :: proc(state: ^Projects_State, path: string) -> bool {
	cache_data, ok := snapshot_projects_cache(state, context.temp_allocator)
	if !ok {
		log.warn("Cannot dump projects cache: not filled")
		return false
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

restore_projects_cache :: proc(state: ^Projects_State, path: string) -> bool {
	json_bytes, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != os.ERROR_NONE {
		log.errorf("Failed to read projects cache from %s", path)
		return false
	}

	sync.lock(&state.cache_mu)
	defer sync.unlock(&state.cache_mu)
	cache_data: Projects_Cache_Serializable
	unmarshal_err := json.unmarshal(json_bytes, &cache_data, allocator = state.cache.allocator)
	if unmarshal_err != nil {
		log.errorf("Failed to unmarshal projects cache: %v", unmarshal_err)
		return false
	}

	state.cache.gitlab = cache_data.gitlab
	state.cache.github = cache_data.github
	state.cache.status = .Filled

	log.infof("Projects cache restored from %s", path)
	return true
}

projects_state_init :: proc(state: ^Projects_State, generator: ^rand.Generator, allocator := context.allocator) -> mem.Allocator_Error {
	sync.lock(&state.cache_mu)
	defer sync.unlock(&state.cache_mu)
	if state.cache != nil {
		log.warn("Projects cache already initialized")
		return .None
	}

	state.allocator = allocator
	state.random_generator = generator
	state.cache = new(Projects_Cache, allocator) or_return
	if err := virtual.arena_init_growing(&state.cache.arena); err != .None {
		free(state.cache, allocator)
		state.cache = nil
		return err
	}
	state.cache.allocator = virtual.arena_allocator(&state.cache.arena)
	state.cache.status = .Empty
	log.info("Projects cache initialized")
	return .None
}



projects_state_destroy :: proc(state: ^Projects_State) {
	sync.lock(&state.refresh_mu)
	defer sync.unlock(&state.refresh_mu)
	sync.lock(&state.cache_mu)
	defer sync.unlock(&state.cache_mu)
	if state.cache != nil {
		virtual.arena_destroy(&state.cache.arena)
		free(state.cache, state.allocator)
		state.cache = nil
	}
}

first_load_projects_cache :: proc(
	state: ^Projects_State,
	config: ^Config,
	me: ^Me_Info,
	generator: ^rand.Generator,
	allocator := context.allocator,
) -> mem.Allocator_Error {
	log.info("Initializing projects cache.")
	if err := projects_state_init(state, generator, allocator); err != .None {
		log.error("Could not initialize projects cache.")
		return err
	}

	if os.exists(PROJECTS_CACHE_FILE) {
		log.info("Found cached projects file, loading from disk")
		if restore_projects_cache(state, PROJECTS_CACHE_FILE) {
			return .None
		}
		log.warn("Failed to restore cache from disk, will fetch fresh")
	}

	_, fetch_err := fetch_projects(state, config, me, use_cache = false)
	if fetch_err.type != .None {
		log.error(fetch_err.msg)
	}
	return .None
}
