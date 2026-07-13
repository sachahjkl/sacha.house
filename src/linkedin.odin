package main

import "core:encoding/json"
import "core:fmt"
import "core:log"

Linkedin_Day :: struct {
	day:   int,
	month: int,
	year:  int,
}


LINKEDIN_MONTH_NAMES :: [?]string {
	"",
	"Jan",
	"Feb",
	"Mar",
	"Apr",
	"May",
	"Jun",
	"Jul",
	"Aug",
	"Sep",
	"Oct",
	"Nov",
	"Dec",
}

format_linkedin_date :: proc(day: Linkedin_Day) -> string {
	if day.year == 0 {
		return "Present"
	}
	month_names: [13]string = LINKEDIN_MONTH_NAMES
	return fmt.tprintf("%s %d", month_names[day.month], day.year)
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
}

get_embedded_profile_string :: proc(store: ^Static_Store) -> Maybe(string) {
	static_profile, ok := store.files["linkedin_profile.json"]
	if ok && static_profile.data != nil {
		return string(static_profile.data)
	}
	return nil
}

get_embedded_profile :: proc(store: ^Static_Store) -> (profile: Linkedin_Profile, err: Error) {
	static_profile, ok := store.files["linkedin_profile.json"]
	if !ok || static_profile.data == nil {
		return {}, Error{type = .None}
	}
	if json.unmarshal(static_profile.data, &profile, allocator = context.temp_allocator) != nil {
		msg := "JSON unmarshal error"
		log.error(msg)
		return {}, Error{type = .JSON_Unmarshal, msg = msg}
	}
	return profile, Error{type = .None}
}
