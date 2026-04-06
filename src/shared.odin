package main

import "core:fmt"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"



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
	Title:    string,
	SEO:      SEO_Data,
	Footer:   Footer_Data,
	NavItems: []NavItem,
	StyleVersion: string,
	HotReload:    bool,
}


TITLE := ME.siteTitle
DESCRIPTION := ME.siteTitle
IMAGE := "/favicon_shadow.png"
AUTHOR := ME.fullName

create_base_page_data :: proc(
	data: Maybe_SEO_Data,
	active_pathname: string,
	is_admin: bool = false,
) -> Base_Page_Data {
	// check each field of the SEO_Data struct and assign a default value if it is nil
	title := data.title
	description := data.description
	author := data.author
	image := data.image

	if title == nil {
		title = TITLE
	}
	if description == nil {
		description = DESCRIPTION
	}
	if author == nil {
		author = AUTHOR
	}
	if image == nil {
		image = IMAGE
	}

	nav_items := compute_nav_items(active_pathname, is_admin)
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
			gitRepoId = APP_CONFIG.GIT_REPO_ID,
			version = VERSION,
		},
		NavItems = nav_items,
		StyleVersion = style_version,
		HotReload = HOT_RELOAD,
	}
}
