package main

import "core:encoding/json"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"

GIT_COMMIT_HASH :: #config(GIT_COMMIT_HASH, "dev")
VERSION :: #config(VERSION, "dev")

Config :: struct {
	GITHUB_REST_API_ENDPOINT:    string,
	GITLAB_API_ENDPOINT:         string,
	GITHUB_GRAPHQL_API_ENDPOINT: string,
	GITLAB_BEARER_TOKEN:         string,
	GITHUB_BEARER_TOKEN:         string,
	ADMIN_IPS:                   []string,
	GIT_REPO_ID:                 string,
	ADMIN_PASSWORD_HASH:         string,
	PASSWORD_SALT:               string,
	WEBAUTHN_CREDENTIALS_FILE:   string,
	WEBAUTHN_RP_ID:              string,
	WEBAUTHN_ORIGIN:             string,
	WEBAUTHN_REQUIRE_USER_VERIFICATION: bool,
	TRUST_PROXY_HTTPS:           bool,
	PASTE_ENABLED:               bool,
	PASTE_SECRETS_FILE:          string,
	PASTE_MAX_BODY_BYTES:        int,
	PASTE_MAX_LIST_ITEMS:        int,
}

PASTE_SECRETS_MAX_FILE_BYTES :: 64 * 1024

Paste_Secrets_Load_Error :: enum {
	None,
	Missing_Path,
	Open,
	Too_Large,
	Read,
	Invalid_JSON,
	Invalid_Secrets,
	Allocation,
}

DEFAULT_CONFIG :: Config {
	GITHUB_REST_API_ENDPOINT = "https://api.github.com",
	GITLAB_API_ENDPOINT = "https://gitlab.com/api/graphql",
	GITHUB_GRAPHQL_API_ENDPOINT = "https://api.github.com/graphql",
	GITLAB_BEARER_TOKEN = "",
	GITHUB_BEARER_TOKEN = "",
	ADMIN_IPS = {},
	GIT_REPO_ID = "",
	ADMIN_PASSWORD_HASH = "",
	PASSWORD_SALT = "",
	WEBAUTHN_CREDENTIALS_FILE = "webauthn_credentials.json",
	WEBAUTHN_RP_ID = "",
	WEBAUTHN_ORIGIN = "",
	WEBAUTHN_REQUIRE_USER_VERIFICATION = true,
	TRUST_PROXY_HTTPS = false,
	PASTE_ENABLED = false,
	PASTE_SECRETS_FILE = "paste-secrets.json",
	PASTE_MAX_BODY_BYTES = 262144,
	PASTE_MAX_LIST_ITEMS = 200,
}

Config_Error :: enum {
	None,
	Missing,
	Read,
	Decode,
	Invalid,
	Allocation,
}

get_config_path :: proc() -> string {
	config_path := os.get_env_alloc("CONFIG_PATH", context.temp_allocator)
	if config_path != "" {
		return config_path
	}
	return "config.json"
}

init_default_config :: proc(config_path: string) {
	log.infof("Config file not found at %s, creating default config", config_path)

	json_bytes, marshal_err := json.marshal(DEFAULT_CONFIG, {pretty = true}, context.temp_allocator)
	if marshal_err != nil {
		log.errorf("Failed to marshal default config: %v", marshal_err)
		return
	}

	if err := os.write_entire_file_from_bytes(config_path, json_bytes); err != os.ERROR_NONE {
		log.errorf("Failed to write default config to %s", config_path)
		return
	}

	log.infof("Default config file created at %s", config_path)
	log.info("Please edit the config file with your settings and restart the application")
}

clone_config_string :: proc(value: string, allocator: mem.Allocator) -> (string, Config_Error) {
	result, err := strings.clone(value, allocator)
	if err != .None {
		return "", .Allocation
	}
	return result, .None
}

load_paste_secrets :: proc(
	path: string,
	allocator: mem.Allocator,
) -> (Paste_Secrets_Config, Paste_Secrets_Load_Error) {
	if path == "" {
		return {}, .Missing_Path
	}

	file, open_err := os.open(path, os.O_RDONLY)
	if open_err != os.ERROR_NONE {
		return {}, .Open
	}
	defer os.close(file)

	size, size_err := os.file_size(file)
	if size_err != os.ERROR_NONE || size < 0 {
		return {}, .Read
	}
	if size > PASTE_SECRETS_MAX_FILE_BYTES {
		return {}, .Too_Large
	}

	raw, alloc_err := make([]byte, int(size), allocator)
	if alloc_err != .None {
		return {}, .Allocation
	}
	defer {
		paste_wipe_bytes(raw)
		delete(raw, allocator)
	}

	if len(raw) > 0 {
		read_count, _ := os.read_at(file, raw, 0)
		if read_count != len(raw) {
			return {}, .Read
		}
	}
	final_size, final_size_err := os.file_size(file)
	if final_size_err != os.ERROR_NONE || final_size != size {
		return {}, .Read
	}

	if shape_err := paste_secrets_json_validate(string(raw)); shape_err != .None {
		return {}, .Invalid_JSON
	}

	secrets: Paste_Secrets_Config
	if unmarshal_err := json.unmarshal(raw, &secrets, .JSON, allocator); unmarshal_err != nil {
		paste_secrets_destroy(&secrets, allocator)
		return {}, .Invalid_JSON
	}
	if validation_err := paste_secrets_validate(&secrets); validation_err != .None {
		paste_secrets_destroy(&secrets, allocator)
		return {}, .Invalid_Secrets
	}
	return secrets, .None
}

load_config :: proc(config_path: string, allocator: mem.Allocator) -> (Config, Config_Error) {
	if !os.exists(config_path) {
		init_default_config(config_path)
		return {}, .Missing
	}

	config_bytes, err := os.read_entire_file_from_path(config_path, context.temp_allocator)
	if err != os.ERROR_NONE {
		log.errorf("Could not read config file: %s", config_path)
		return {}, .Read
	}

	parsed := DEFAULT_CONFIG
	if unmarshal_err := json.unmarshal(config_bytes, &parsed, allocator = context.temp_allocator); unmarshal_err != nil {
		log.errorf("Could not unmarshal config file: %v", unmarshal_err)
		return {}, .Decode
	}

	if parsed.PASTE_MAX_BODY_BYTES < PASTE_STORE_MIN_BODY_BYTES ||
	   parsed.PASTE_MAX_BODY_BYTES > PASTE_STORE_MAX_BODY_BYTES ||
	   parsed.PASTE_MAX_LIST_ITEMS < PASTE_STORE_MIN_LIST_ITEMS ||
	   parsed.PASTE_MAX_LIST_ITEMS > PASTE_STORE_MAX_LIST_ITEMS {
		log.error("Paste limits are outside the allowed ranges")
		return {}, .Invalid
	}

	config: Config
	clone_err: Config_Error
	config.GITHUB_REST_API_ENDPOINT, clone_err = clone_config_string(parsed.GITHUB_REST_API_ENDPOINT, allocator)
	if clone_err != .None {
		return {}, clone_err
	}
	config.GITLAB_API_ENDPOINT, clone_err = clone_config_string(parsed.GITLAB_API_ENDPOINT, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.GITHUB_GRAPHQL_API_ENDPOINT, clone_err = clone_config_string(parsed.GITHUB_GRAPHQL_API_ENDPOINT, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.GITLAB_BEARER_TOKEN, clone_err = clone_config_string(parsed.GITLAB_BEARER_TOKEN, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.GITHUB_BEARER_TOKEN, clone_err = clone_config_string(parsed.GITHUB_BEARER_TOKEN, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.GIT_REPO_ID, clone_err = clone_config_string(parsed.GIT_REPO_ID, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.ADMIN_PASSWORD_HASH, clone_err = clone_config_string(parsed.ADMIN_PASSWORD_HASH, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.PASSWORD_SALT, clone_err = clone_config_string(parsed.PASSWORD_SALT, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.WEBAUTHN_CREDENTIALS_FILE, clone_err = clone_config_string(parsed.WEBAUTHN_CREDENTIALS_FILE, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.WEBAUTHN_RP_ID, clone_err = clone_config_string(parsed.WEBAUTHN_RP_ID, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.WEBAUTHN_ORIGIN, clone_err = clone_config_string(parsed.WEBAUTHN_ORIGIN, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}

	admin_ips, alloc_err := make([]string, len(parsed.ADMIN_IPS), allocator)
	if alloc_err != .None {
		config_destroy(&config, allocator)
		return {}, .Allocation
	}
	config.ADMIN_IPS = admin_ips
	for value, i in parsed.ADMIN_IPS {
		config.ADMIN_IPS[i], clone_err = clone_config_string(value, allocator)
		if clone_err != .None {
			config_destroy(&config, allocator)
			return {}, clone_err
		}
	}
	config.PASTE_SECRETS_FILE, clone_err = clone_config_string(parsed.PASTE_SECRETS_FILE, allocator)
	if clone_err != .None {
		config_destroy(&config, allocator)
		return {}, clone_err
	}
	config.WEBAUTHN_REQUIRE_USER_VERIFICATION = parsed.WEBAUTHN_REQUIRE_USER_VERIFICATION
	config.TRUST_PROXY_HTTPS = parsed.TRUST_PROXY_HTTPS
	config.PASTE_ENABLED = parsed.PASTE_ENABLED
	config.PASTE_MAX_BODY_BYTES = parsed.PASTE_MAX_BODY_BYTES
	config.PASTE_MAX_LIST_ITEMS = parsed.PASTE_MAX_LIST_ITEMS

	log.infof("Config loaded from %s", config_path)
	return config, .None
}

config_destroy :: proc(config: ^Config, allocator := context.allocator) {
	if config == nil {
		return
	}
	delete(config.GITHUB_REST_API_ENDPOINT, allocator)
	delete(config.GITLAB_API_ENDPOINT, allocator)
	delete(config.GITHUB_GRAPHQL_API_ENDPOINT, allocator)
	delete(config.GITLAB_BEARER_TOKEN, allocator)
	delete(config.GITHUB_BEARER_TOKEN, allocator)
	delete(config.GIT_REPO_ID, allocator)
	delete(config.ADMIN_PASSWORD_HASH, allocator)
	delete(config.PASSWORD_SALT, allocator)
	delete(config.WEBAUTHN_CREDENTIALS_FILE, allocator)
	delete(config.WEBAUTHN_RP_ID, allocator)
	delete(config.WEBAUTHN_ORIGIN, allocator)
	delete(config.PASTE_SECRETS_FILE, allocator)
	for value in config.ADMIN_IPS {
		delete(value, allocator)
	}
	delete(config.ADMIN_IPS, allocator)
	config^ = {}
}
