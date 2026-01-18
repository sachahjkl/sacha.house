package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:time"

import client "lib:odin-http/client"

Linkedin_Day :: struct {
	day:   int,
	month: int,
	year:  int,
}

format_linkedin_day :: proc(day: Linkedin_Day) -> string {
	return fmt.tprintf("%d%02d%02d", day.year, day.month, day.day)
}

Experience :: struct {
	starts_at:                    Linkedin_Day,
	ends_at:                      Linkedin_Day,
	company:                      string,
	company_linkedin_profile_url: string,
	title:                        string,
	description:                  string,
	location:                     string,
	logo_url:                     string,
}

Education :: struct {
	starts_at:                   Linkedin_Day,
	ends_at:                     Linkedin_Day,
	field_of_study:              string,
	degree_name:                 string,
	school:                      string,
	school_linkedin_profile_url: string,
	description:                 string,
	logo_url:                    string,
}

Linkedin_Profile :: struct {
	experiences: []Experience,
	education:   []Education,
	// ... other fields can be added if needed
}

Gist_File :: struct {
	content: string,
}

Gist_Request :: struct {
	files: map[string]Gist_File,
}

// Global cache for the linkedin profile to avoid fetching it multiple times
linkedin_profile_cache: ^Linkedin_Profile
linkedin_profile_cache_time: time.Time

fetch_linkedin_profile :: proc() -> (profile: Linkedin_Profile, err: Error) {
	// Check cache first
	if linkedin_profile_cache != nil &&
	   time.diff(time.now(), linkedin_profile_cache_time) < 3600 * time.Second {
		return linkedin_profile_cache^, Error{type = .None}
	}

	proxycurl_token := APP_CONFIG.PROXYCURL_BEARER_TOKEN
	if proxycurl_token == "" {
		msg := "PROXYCURL_BEARER_TOKEN is not set"
		log.error(msg)
		return {}, Error{type = .Authorization, msg = msg}
	}

	linkedin_url := ME.linkedin
	if linkedin_url == "" {
		msg := "linkedin_url is not set"
		log.error(msg)
		return {}, Error{type = .Validation, msg = msg}
	}

	client_req: client.Request
	client.request_init(&client_req, .Get)
	defer client.request_destroy(&client_req)

	with_bearer_auth(&client_req, proxycurl_token)
	url := fmt.tprintf(
		"%s/proxycurl/api/v2/linkedin?url=%s&fallback_to_cache=on-error",
		APP_CONFIG.PROXYCURL_API_ENDPOINT,
		linkedin_url,
	)

	client_res, req_err := client.request(&client_req, url)
	if req_err != nil {
		msg := fmt.tprintf("Request failed: %s", req_err)
		log.error(msg)
		return {}, Error{type = .Network, msg = msg}
	}
	defer client.response_destroy(&client_res)

	body, allocation, berr := client.response_body(&client_res)
	if berr != nil {
		msg := fmt.tprintf("Error retrieving linkedin profile body: %s", berr)
		log.error(msg)
		return {}, Error{type = .Network, msg = msg}
	}
	defer client.body_destroy(body, allocation)

	body_bytes, ok_body := body.(client.Body_Plain)
	if !ok_body {
		msg := "Error converting linkedin profile body to bytes"
		log.error(msg)
		return {}, Error{type = .Validation, msg = msg}
	}
	if json.unmarshal(transmute([]u8)body_bytes, &profile, allocator = context.temp_allocator) != nil {
		msg := "JSON unmarshal error"
		log.error(msg)
		return {}, Error{type = .JSON_Unmarshal, msg = msg}
	}

	// Update cache
	if linkedin_profile_cache != nil {
		free(linkedin_profile_cache)
	}
	linkedin_profile_cache = new(Linkedin_Profile)
	linkedin_profile_cache^ = profile
	linkedin_profile_cache_time = time.now()

	return profile, Error{type = .None}
}

get_gist_profile_string :: proc() -> Maybe(string) {
	static_profile := static_files["linkedin_profile.json"]
	if static_profile.data != nil {
		return string(static_profile.data)
	}
	return nil
}

get_gist_profile :: proc() -> (profile: Linkedin_Profile, err: Error) {

	// first check if the gist json data is available in the static file linkedin_profile.json

	static_profile := static_files["linkedin_profile.json"]
	if static_profile.data != nil {
		if json.unmarshal(static_profile.data, &profile, allocator = context.temp_allocator) != nil {
			msg := "JSON unmarshal error"
			log.error(msg)
			return {}, Error{type = .JSON_Unmarshal, msg = msg}
		}
		return profile, Error{type = .None}
	}

	return {}, Error{type = .None}
}
