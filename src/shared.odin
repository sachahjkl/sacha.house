package main

import "core:fmt"
import "core:strings"
import "core:time"

SEO_Data :: struct {
	title:       string,
	description: string,
	author:      string,
	image:       string,
}

Maybe_SEO_Data :: struct {
	title:       Maybe(string),
	description: Maybe(string),
	author:      Maybe(string),
	image:       Maybe(string),
}

Footer_Data :: struct {
	year:       int,
	commitHash: string,
	gitRepoId:  string,
	version:    string,
}

Base_Page_Data :: struct {
	Title:         string,
	SEO:           SEO_Data,
	Footer:        Footer_Data,
	NavItems:      []NavItem,
	StyleVersion:  string,
	Language:      string,
	CanonicalURL:  string,
	LoadHTMX:      bool,
	LoadAdminJS:   bool,
	HotReload:     bool,
}

DEFAULT_SEO_IMAGE :: "https://sacha.house/static/favicon_shadow.png"

create_base_page_data :: proc(
	app: ^App_State,
	data: Maybe_SEO_Data,
	active_pathname: string,
	is_admin: bool = false,
	language: string = "en",
) -> Base_Page_Data {
	title := data.title
	description := data.description
	author := data.author
	image := data.image

	if title == nil {
		title = app.me.siteTitle
	}
	if description == nil {
		description = app.me.siteTitle
	}
	if author == nil {
		author = app.me.fullName
	}
	if image == nil {
		image = DEFAULT_SEO_IMAGE
	}

	style_version := GIT_COMMIT_HASH
	when ODIN_DEBUG {
		style_version = fmt.tprintf("%d", time.time_to_unix_nano(time.now()))
	}

	return Base_Page_Data {
		Title = title.(string),
		SEO = SEO_Data {
			title = title.(string),
			description = description.(string),
			author = author.(string),
			image = image.(string),
		},
		Footer = Footer_Data {
			year = time.year(time.now()),
			commitHash = GIT_COMMIT_HASH,
			gitRepoId = app.config.GIT_REPO_ID,
			version = VERSION,
		},
		NavItems = compute_nav_items(active_pathname, is_admin),
		StyleVersion = style_version,
		HotReload = app.options.hot_reload,
		Language = language,
		CanonicalURL = strings.concatenate({"https://sacha.house", active_pathname}, context.temp_allocator),
		LoadHTMX = active_pathname == "/admin/login" || active_pathname == "/admin/webauthn",
		LoadAdminJS = strings.has_prefix(active_pathname, "/admin"),
	}
}
