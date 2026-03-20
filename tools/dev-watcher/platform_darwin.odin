#+build darwin
package main

import "core:fmt"

// Stub for MacOS/Darwin
// TODO: Implement Kqueue or FSEvents

Process_Handle :: int
INVALID_PROCESS_HANDLE :: -1

server_process: Process_Handle = INVALID_PROCESS_HANDLE
server_running := false

get_build_args :: proc() -> string {
	return "build-dev"
}

start_server :: proc() {
	fmt.println("[dev] MacOS watcher not implemented yet")
}

stop_server :: proc() {}

init_watcher :: proc() -> bool {
	fmt.println("[dev] MacOS watcher not implemented yet")
	return false
}

cleanup_watcher :: proc() {}

wait_for_changes :: proc() -> bool {
	return false
}

consume_pending_changes :: proc() {}
