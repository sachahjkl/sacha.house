package main

import "core:crypto"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:time"
import "core:time/datetime"

App_Options :: struct {
	hot_reload: bool,
	port:       u16,
}

App_Init_Error :: enum {
	None,
	Timezone,
	Static,
	Projects,
	Sessions,
	WebAuthn,
	Paste_Secrets,
	Paste_Service,
}

App_Init_Stage :: enum {
	None,
	Config,
	Random,
	Timezone,
	Identity,
	Static,
	Blog,
	Projects,
	Sessions,
	WebAuthn,
	Pastes,
}

App_State :: struct {
	allocator:        mem.Allocator,
	config:           Config,
	options:          App_Options,
	me:               Me_Info,
	timezone:         ^datetime.TZ_Region,
	static:           Static_Store,
	blog:             Blog_Store,
	projects:         Projects_State,
	sessions:         Session_Storage,
	webauthn:         WebAuthn_Storage,
	pastes:           Paste_Service,
	random_generator: rand.Generator,
	server_boot_id:   string,
	init_stage:       App_Init_Stage,
}

app_state_init :: proc(
	app: ^App_State,
	config: Config,
	options: App_Options,
	allocator := context.allocator,
) -> App_Init_Error {
	app.allocator = allocator
	app.config = config
	app.options = options
	app.init_stage = .Config

	app.random_generator = crypto.random_generator()
	app.init_stage = .Random

	tz, timezone_ok := timezone_init("Europe/Paris")
	if !timezone_ok {
		app_state_destroy(app)
		return .Timezone
	}
	app.timezone = tz
	app.init_stage = .Timezone

	app.me = me_init(allocator)
	app.init_stage = .Identity

	if err := static_store_init(&app.static, allocator); err != .None {
		app_state_destroy(app)
		return .Static
	}
	app.init_stage = .Static

	app.blog = Blog_Store {
		root = "data/blog",
		author = app.me.fullName,
	}
	app.init_stage = .Blog

	if err := first_load_projects_cache(&app.projects, &app.config, &app.me, &app.random_generator, allocator); err != .None {
		app_state_destroy(app)
		return .Projects
	}
	app.init_stage = .Projects

	if err := session_storage_init(&app.sessions, allocator); err != .None {
		app_state_destroy(app)
		return .Sessions
	}
	app.init_stage = .Sessions

	if err := webauthn_storage_init(
		&app.webauthn,
		&app.config,
		&app.random_generator,
		allocator,
	); err != .None {
		app_state_destroy(app)
		return .WebAuthn
	}
	app.init_stage = .WebAuthn

	paste_secrets: Paste_Secrets_Config
	if app.config.PASTE_ENABLED {
		secrets_err: Paste_Secrets_Load_Error
		paste_secrets, secrets_err = load_paste_secrets(app.config.PASTE_SECRETS_FILE, allocator)
		if secrets_err != .None {
			app_state_destroy(app)
			return .Paste_Secrets
		}
	}
	paste_err := paste_service_init(
		&app.pastes,
		app.config.PASTE_ENABLED,
		app.config.GITHUB_REST_API_ENDPOINT,
		&paste_secrets,
		app.config.PASTE_MAX_BODY_BYTES,
		app.config.PASTE_MAX_LIST_ITEMS,
		allocator,
	)
	if app.config.PASTE_ENABLED {
		paste_secrets_destroy(&paste_secrets, allocator)
	}
	if paste_err.kind != .None {
		app_state_destroy(app)
		return .Paste_Service
	}
	app.init_stage = .Pastes

	if app.options.hot_reload {
		app.server_boot_id = fmt.aprintf(
			"%d",
			time.time_to_unix_nano(time.now()),
			allocator = allocator,
		)
	}
	return .None
}

app_state_destroy :: proc(app: ^App_State) {
	if app == nil {
		return
	}

	if app.server_boot_id != "" {
		delete(app.server_boot_id, app.allocator)
	}
	if app.init_stage >= .Pastes {
		paste_service_destroy(&app.pastes)
	}
	if app.init_stage >= .WebAuthn {
		webauthn_storage_destroy(&app.webauthn)
	}
	if app.init_stage >= .Sessions {
		session_storage_destroy(&app.sessions)
	}
	if app.init_stage >= .Projects {
		projects_state_destroy(&app.projects)
	}
	if app.init_stage >= .Blog {
		app.blog = {}
	}
	if app.init_stage >= .Static {
		static_store_destroy(&app.static)
	}
	if app.init_stage >= .Identity {
		me_destroy(&app.me, app.allocator)
	}
	if app.init_stage >= .Timezone {
		timezone_destroy(app.timezone)
	}
	if app.init_stage >= .Config {
		config_destroy(&app.config, app.allocator)
	}
	app^ = {}
}
