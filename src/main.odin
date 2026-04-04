package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"

import "core:debug/trace"


LoggerOpts :: log.Options{.Level, .Time, .Short_File_Path, .Line, .Terminal_Color, .Thread_Id}

TRACK_LEAKS :: #config(TRACK_LEAKS, true)
HOT_RELOAD := false
globals_cleaned_up := false

cleanup_globals :: proc() {
	if globals_cleaned_up {
		return
	}
	globals_cleaned_up = true

	// NOTE(sachahjkl):
	// Cleanup global resources before exit
	cleanup_timezone()
	cleanup_static_files()
	cleanup_me()

	// Cleanup linkedin profile cache
	if linkedin_profile_cache != nil {
		free(linkedin_profile_cache)
		linkedin_profile_cache = nil
	}
}

main :: proc() {
	level := log.Level.Debug when ODIN_DEBUG else log.Level.Info
	context.logger = log.create_console_logger(level, LoggerOpts)
	defer cleanup_globals()

	when ODIN_DEBUG {
		trace.init(&global_trace_ctx)
		defer trace.destroy(&global_trace_ctx)
		context.assertion_failure_proc = debug_trace_assertion_failure_proc
	}

	// NOTE(sachahjkl): What a mess.
	init_random_generator()

	when TRACK_LEAKS {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
	}

	handle_cli_args()

	if !init_timezone() {
		log.error("Failed to initialize timezone, exiting...")
		os.exit(1)
	}
	log.info("Timezone initialized.")

	if !load_config() {
		log.error("Failed to load config, exiting...")
		os.exit(1)
	}
	log.info("Config loaded.")

	// NOTE(sachahjkl): The order of initialization is important.
	init_static_files()
	init_me()
	log.info("Static files and ME initialized.")

	server_start()

	cleanup_globals()

	when TRACK_LEAKS {
		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
		}
		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
		}
	}
}
