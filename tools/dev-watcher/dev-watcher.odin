package main

import "core:c/libc"
import "core:fmt"
import "core:strings"
import "core:time"

// Configuration
WATCH_DIRS := []string{"src", "lib", "styles"}
EXTENSIONS := []string{".odin", ".twig", ".css", ".js"}
BUILD_CMD := "just"

main :: proc() {
	fmt.println("[dev] Starting dev watcher...")

	if !init_watcher() {
		fmt.println("[dev] Failed to initialize watcher")
		return
	}
	defer cleanup_watcher()

	// Initial build and run
	if build_project() {
		start_server()
	}

	// Watch loop
	for {
		// blocking wait
		if wait_for_changes() {
			if ignore_next_change {
				ignore_next_change = false
				consume_pending_changes()
				continue
			}

			// Measure time
			start_time := time.now()
			fmt.println("[dev] Changes detected...")

			// Stop server BEFORE building to release file lock on Windows
			stop_server()

			// Debounce
			time.sleep(100 * time.Millisecond)

			// Consume any pending events during debounce
			consume_pending_changes()

			fmt.println("[dev] Rebuilding... ")
			if build_project() {
				ignore_next_change = true
				elapsed := time.since(start_time)
				fmt.printfln("[dev] Dev watcher finished (took %v)", elapsed)
				start_server()
			}
		}
	}
}

server_running := false
ignore_next_change := false

start_server_if_needed :: proc() {
	if !server_running {
		start_server()
	}
}

build_project :: proc() -> bool {
	fmt.println("[dev] Building...")

	args := get_build_args()
	cmd := fmt.tprintf("%s %s", BUILD_CMD, args)

	// NOTE(Sacha):
	// While libc.system is blocking, it is the simplest way to run a shell command like 'just'
	// without manually parsing arguments and handling path resolution for the executable.
	// Since 'build_project' is intended to be a blocking operation that prevents the server
	// from starting until it completes, this is acceptable.
	res := libc.system(strings.clone_to_cstring(cmd))

	if res == 0 {
		fmt.println("[dev] Build successful.")
		return true
	} else {
		fmt.println("[dev] Build failed.")
		return false
	}
}
