package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"

import "core:debug/trace"

LoggerOpts :: log.Options{.Level, .Time, .Short_File_Path, .Line, .Terminal_Color, .Thread_Id}

TRACK_LEAKS :: #config(TRACK_LEAKS, true)

main :: proc() {
	level := log.Level.Debug when ODIN_DEBUG else log.Level.Info
	context.logger = log.create_console_logger(level, LoggerOpts)
	original_allocator := context.allocator
	defer context.allocator = original_allocator

	when ODIN_DEBUG {
		trace.init(&global_trace_ctx)
		context.assertion_failure_proc = debug_trace_assertion_failure_proc
	}

	when TRACK_LEAKS {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
	}

	cli_options, action, args_ok := parse_cli_args(os.args[1:])
	if !args_ok {
		_ = run_cli_action(.Help, &cli_options, nil)
		return
	}
	if action == .Help || action == .Version {
		_ = run_cli_action(action, &cli_options, nil)
		return
	}

	config, config_err := load_config(get_config_path(), context.allocator)
	if config_err != .None {
		log.errorf("Failed to load config: %v", config_err)
		return
	}

	if action == .Hash_Password {
		exit_code := run_cli_action(action, &cli_options, &config)
		config_destroy(&config, context.allocator)
		if exit_code != 0 {
			os.exit(exit_code)
		}
		return
	}

	app: App_State
	init_err := app_state_init(
		&app,
		config,
		App_Options {
			hot_reload = cli_options.hot_reload,
			port = cli_options.port,
		},
		context.allocator,
	)
	if init_err != .None {
		log.errorf("Failed to initialize application state: %v", init_err)
		return
	}
	defer app_state_destroy(&app)

	server_start(&app)
	app_state_destroy(&app)

	when TRACK_LEAKS {
		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
		}
		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
		}
	}
}
