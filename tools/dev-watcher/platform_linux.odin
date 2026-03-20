#+build linux
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/linux"
import "core:sys/posix"

// --- Process Management ---

Process_Handle :: posix.pid_t
INVALID_PROCESS_HANDLE :: -1

server_process: Process_Handle = INVALID_PROCESS_HANDLE

get_build_args :: proc() -> string {
	return "build-dev"
}

start_server :: proc() {
	if server_running {return}

	fmt.println("[dev] Starting server...")
	cmd := "./sacha.house.dev"
	args := []string{"-dev"}

	pid := posix.fork()
	if pid < 0 {
		fmt.println("[dev] Fork failed")
		return
	}

	if pid == 0 {
		// Child
		c_args := make([]cstring, len(args) + 2)
		c_args[0] = strings.clone_to_cstring(cmd)
		for i in 0 ..< len(args) {
			c_args[i + 1] = strings.clone_to_cstring(args[i])
		}
		c_args[len(args) + 1] = nil
		posix.execvp(c_args[0], raw_data(c_args))
		os.exit(1)
	}

	server_process = pid
	server_running = true
}

stop_server :: proc() {
	if !server_running {return}
	fmt.println("[dev] Stopping server...")
	posix.kill(server_process, posix.SIGTERM)

	status: i32
	posix.waitpid(server_process, &status, 0)

	server_process = INVALID_PROCESS_HANDLE
	server_running = false
}

// --- Watcher (inotify) ---

inotify_fd: i32
inotify_file: ^os.File
watch_descriptors: map[i32]string // wd -> path

init_watcher :: proc() -> bool {
	// inotify_init1(0)
	// Use linux syscall or libc if available.
	// core:sys/linux has inotify_init

	fd, err := linux.inotify_init()
	if err != nil {
		fmt.println("[dev] inotify_init failed")
		return false
	}
	inotify_fd = i32(fd)
	inotify_file = os.new_file(uintptr(inotify_fd), "inotify")

	// Add watches recursively
	for dir in WATCH_DIRS {
		add_watch_recursive(dir)
	}

	return true
}

add_watch_recursive :: proc(dir: string) {
	// IN_MODIFY | IN_CREATE | IN_DELETE | IN_MOVE
	mask := linux.Inotify_Watch_Mask{.MODIFY, .CREATE, .DELETE, .MOVE}

	wd, err := linux.inotify_add_watch(linux.Fd(inotify_fd), dir, mask)
	if err == nil {
		watch_descriptors[i32(wd)] = strings.clone(dir)
		// fmt.printf("[dev] Watched: %s\n", dir)
	} else {
		// fmt.printf("[dev] Failed to watch %s: %v\n", dir, err)
	}

	// Recurse
	f, ferr := os.open(dir)
	if ferr == os.ERROR_NONE {
		defer os.close(f)
		fis, _ := os.read_directory(f, -1, context.temp_allocator)
		defer os.file_info_slice_delete(fis, context.temp_allocator)

		for fi in fis {
			if fi.type == os.File_Type.Directory {
				if fi.name == "." || fi.name == ".." {continue}
				path, _ := os.join_path([]string{dir, fi.name}, context.temp_allocator)
				add_watch_recursive(path)
				// path leaked in map if success, deleted otherwise?
				// wait, filepath.join allocates.
				// if we store it in watch_descriptors, we keep it.
				// otherwise delete(path) here?
				// Actually strings.clone(dir) above clones the input string.
				// So we can delete path if we passed it...
				// No, recursive call uses it.
				// Let's just leak path strings for dev tool simplicity or manage memory better if crashing.
			}
		}
	}
}

cleanup_watcher :: proc() {
	os.close(inotify_file)
}

wait_for_changes :: proc() -> bool {
	// Read from inotify_fd
	// This blocks

	buf: [4096]byte
	n, err := os.read(inotify_file, buf[:])
	if err != os.ERROR_NONE || n <= 0 {
		return false
	}

	// We got some events
	// Process events to see if we need to add new watches (for new directories)

	// Parsing inotify events is a bit manual with raw buffer
	// struct inotify_event {
	//    int      wd;
	//    uint32_t mask;
	//    uint32_t cookie;
	//    uint32_t len;
	//    char     name[];
	// };

	offset := 0
	for offset < n {
		if offset + size_of(linux.Inotify_Event) > n {break}

		event := cast(^linux.Inotify_Event)&buf[offset]

		// Check if it is a directory creation, we need to add watch
		if .ISDIR in event.mask && .CREATE in event.mask {
			// Construct path
			if wd_path, ok := watch_descriptors[i32(event.wd)]; ok {
				name_len := int(event.len)
				if name_len > 0 {
					// name is null terminated string at buf[offset + size_of(linux.Inotify_Event)]
					name_ptr := &buf[offset + size_of(linux.Inotify_Event)]
					name_str := string(cstring(name_ptr))
					new_path, _ := os.join_path([]string{wd_path, name_str}, context.temp_allocator)
					add_watch_recursive(new_path)
				}
			}
		}

		offset += size_of(linux.Inotify_Event) + int(event.len)
	}

	return true
}

consume_pending_changes :: proc() {
	// Read with non-blocking?
	// Or just assume debounce sleep was enough.
	// To do properly we'd need poll/select on fd with 0 timeout.
	// For now, simple sleep in main loop is likely enough.
}
