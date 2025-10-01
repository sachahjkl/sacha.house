package main

import "core:encoding/json"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"

GIT_COMMIT_HASH :: #config(GIT_COMMIT_HASH, "dev")
VERSION_TAG :: #config(VERSION_TAG, "dev")

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

DEFAULT_CONFIG :: Config {
	PROXYCURL_API_ENDPOINT = "https://nubela.co/proxycurl/api/v2/linkedin",
	GITHUB_REST_API_ENDPOINT = "https://api.github.com",
	GITLAB_API_ENDPOINT = "https://gitlab.com/api/graphql",
	GITHUB_GRAPHQL_API_ENDPOINT = "https://api.github.com/graphql",
	HYGRAPH_API_ENDPOINT = "https://api-us-east-1-shared-usea1-02.hygraph.com/v2/cm0g4j8gx017007uvfwvwf3xn/master",
	GITLAB_BEARER_TOKEN = "",
	GITHUB_BEARER_TOKEN = "",
	PROXYCURL_BEARER_TOKEN = "",
	LINKEDIN_GIST_ID = "",
	ADMIN_IPS = {},
	GIT_REPO_ID = "",
	ADMIN_USERNAME = "",
	ADMIN_PASSWORD = "",
}

get_config_path :: proc() -> string {
	config_path := os.get_env("CONFIG_PATH", context.temp_allocator)
	if config_path != "" {
		return config_path
	}
	return "config.json"
}

get_port :: proc() -> int {
	port_str := os.get_env("PORT", context.temp_allocator)
	if port_str != "" {
		port, ok := strconv.parse_int(port_str)
		if ok && port > 0 && port <= 65535 {
			return port
		}
		log.warnf("Invalid PORT value '%s', using default 6969", port_str)
	}
	return 6969
}

init_default_config :: proc(config_path: string) {
	log.infof("Config file not found at %s, creating default config", config_path)
	
	json_bytes, marshal_err := json.marshal(DEFAULT_CONFIG, {pretty = true}, context.temp_allocator)
	if marshal_err != nil {
		log.errorf("Failed to marshal default config: %v", marshal_err)
		return
	}

	if !os.write_entire_file(config_path, json_bytes) {
		log.errorf("Failed to write default config to %s", config_path)
		return
	}

	log.infof("Default config file created at %s", config_path)
	log.info("Please edit the config file with your settings and restart the application")
	return
}

load_config :: proc() -> bool {
	config_path := get_config_path()

	if !os.exists(config_path) {
		init_default_config(config_path)
		return false
	}

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

	log.infof("Config loaded from %s", config_path)
	return true
}
