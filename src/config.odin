package main

import "core:encoding/json"
import "core:log"
import "core:os"
import "core:strings"

GIT_COMMIT_HASH :: #config(GIT_COMMIT_HASH, "dev")

Config :: struct {
	PROXYCURL_API_ENDPOINT:      string,
	GITHUB_REST_API_ENDPOINT:    string,
	GITLAB_API_ENDPOINT:         string,
	GITHUB_GRAPHQL_API_ENDPOINT: string,
	HYGRAPH_API_ENDPOINT:        string,
	GITLAB_BEARER_TOKEN:         string,
	GITHUB_BEARER_TOKEN:         string,
	PROXYCURL_BEARER_TOKEN:      string,
	LINKEDIN_GIST_ID:            string,
	ADMIN_IPS:                   []string,
	GIT_REPO_ID:                 string,
	ADMIN_USERNAME:              string,
	ADMIN_PASSWORD:              string,
}

APP_CONFIG: Config

load_config :: proc() -> bool {
	config_path := "config.json"

	config_bytes, ok := os.read_entire_file(config_path)
	if !ok {
		log.errorf("Could not read config file: %s", config_path)
		return false
	}

	defer delete(config_bytes)

	err := json.unmarshal(config_bytes, &APP_CONFIG, allocator = context.temp_allocator)
	if err != nil {
		log.errorf("Could not unmarshal config file: %v", err)
		return false
	}

	return true
}
