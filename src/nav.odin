package main

import "core:strings"
NavItem :: struct {
	Title:           string,
	Pathname:        string,
	Icon:            string,
	IsActive:        bool,
	PermissionLevel: PermissionLevel,
	CanAccess:       bool,
}

PermissionLevel :: enum {
	None,
	Public,
	Admin,
}

DEFAULT_NAV_ITEMS :: [?]NavItem {
	{
		Title = "home",
		Pathname = "/",
		Icon = "🏠",
		IsActive = false,
		PermissionLevel = .Public,
		CanAccess = true,
	},
	{
		Title = "projects",
		Pathname = "/projects",
		Icon = "📁",
		IsActive = false,
		PermissionLevel = .Public,
		CanAccess = true,
	},
	{
		Title = "blog",
		Pathname = "/blog",
		Icon = "📝",
		IsActive = false,
		PermissionLevel = .Public,
		CanAccess = true,
	},
	{
		Title = "about",
		Pathname = "/about",
		Icon = "📜",
		IsActive = false,
		PermissionLevel = .Public,
		CanAccess = true,
	},
	{
		Title = "admin",
		Pathname = "/admin",
		Icon = "🔒",
		IsActive = false,
		PermissionLevel = .Admin,
		CanAccess = true,
	},
}


compute_nav_items :: proc(active_pathname: string, is_admin := false) -> []NavItem {
	nav_items := make([]NavItem, len(DEFAULT_NAV_ITEMS), context.temp_allocator)
	default_nav_items: [5]NavItem = DEFAULT_NAV_ITEMS
	copy(nav_items, default_nav_items[:])
	for &item in nav_items {
		item.IsActive = false
		if item.PermissionLevel == .Admin {
			item.CanAccess = is_admin
		}

		if item.PermissionLevel == .Public {
			item.CanAccess = true
		}
	}

	for &item, i in nav_items {
		matches := false
		is_root := item.Pathname == "/"
		if is_root {
			matches = active_pathname == "/"
		} else {
			matches = strings.has_prefix(active_pathname, item.Pathname)
		}
		nav_items[i].IsActive = matches
	}

	return nav_items
}
