#+build windows
package main

import "core:fmt"
import "core:strings"
import win "core:sys/windows"

// --- Process Management ---

Process_Handle :: win.HANDLE
INVALID_PROCESS_HANDLE :: cast(Process_Handle)(uintptr(0))

server_process: Process_Handle = INVALID_PROCESS_HANDLE

get_build_args :: proc() -> string {
	return "build ODIN_OUT=sacha.house.dev.exe mode=debug"
}

start_server :: proc() {
	if server_running {return}

	fmt.println("[dev] Starting server...")
	cmd := "sacha.house.dev.exe"
	args := []string{"-dev"}

	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, cmd)
	for arg in args {
		strings.write_string(&sb, " ")
		strings.write_string(&sb, arg)
	}
	full_cmd := strings.to_string(sb)

	si: win.STARTUPINFOW
	si.cb = size_of(si)
	pi: win.PROCESS_INFORMATION

	cmd_wide := win.utf8_to_wstring(full_cmd)

	res := win.CreateProcessW(nil, cmd_wide, nil, nil, false, 0, nil, nil, &si, &pi)

	if !res {
		fmt.println("[dev] Failed to start server process")
		return
	}

	win.CloseHandle(pi.hThread)
	server_process = pi.hProcess
	server_running = true
}

stop_server :: proc() {
	if !server_running {return}
	fmt.println("[dev] Stopping server...")
	win.TerminateProcess(server_process, 0)
	win.CloseHandle(server_process)
	server_process = INVALID_PROCESS_HANDLE
	server_running = false
}

// --- Watcher ---

change_handles: [dynamic]win.HANDLE

init_watcher :: proc() -> bool {
	for dir in WATCH_DIRS {
		dir_wide := win.utf8_to_wstring(dir)

		// FILE_NOTIFY_CHANGE_LAST_WRITE  = 0x00000010
		// FILE_NOTIFY_CHANGE_FILE_NAME   = 0x00000001
		// FILE_NOTIFY_CHANGE_DIR_NAME    = 0x00000002
		// FILE_NOTIFY_CHANGE_CREATION    = 0x00000040
		filter: u32 = 0x00000010 | 0x00000001 | 0x00000002 | 0x00000040

		h := win.FindFirstChangeNotificationW(
			cast(^u16)dir_wide,
			true, // watch subtree
			filter,
		)

		if h == win.INVALID_HANDLE_VALUE {
			fmt.printf("[dev] Failed to create watcher for %s\n", dir)
			return false
		}
		append(&change_handles, h)
	}
	return true
}

cleanup_watcher :: proc() {
	for h in change_handles {
		win.FindCloseChangeNotification(h)
	}
	delete(change_handles)
}

wait_for_changes :: proc() -> bool {
	if len(change_handles) == 0 {return false}

	// WaitForMultipleObjects
	// nCount, lpHandles, bWaitAll, dwMilliseconds
	count := u32(len(change_handles))
	handles := raw_data(change_handles)

	// Wait indefinitely
	wait_res := win.WaitForMultipleObjects(count, handles, false, win.INFINITE)

	// WAIT_OBJECT_0 = 0
	if wait_res >= 0 && wait_res < count {
		// One of the handles triggered.
		// We need to reset changes for NEXT wait, but FindFirstChangeNotification handle
		// needs FindNextChangeNotification to reset?
		// Actually, WaitForMultipleObjects returns when the event is signaled.
		// For change notifications, the handle is signaled when a change occurs.
		// To wait for the next change, we call FindNextChangeNotification.

		// However, since we want to return true and let the main loop handle logic,
		// we should probably handle the reset here or in consume_pending_changes.

		// Let's mark which one fired and reset it.
		index := wait_res
		if !win.FindNextChangeNotification(change_handles[index]) {
			fmt.println("[dev] FindNextChangeNotification failed")
			return false
		}
		return true
	}

	return false
}

consume_pending_changes :: proc() {
	// Poll with 0 timeout to see if other handles also fired or if they fire again immediately
	count := u32(len(change_handles))
	handles := raw_data(change_handles)

	for {
		wait_res := win.WaitForMultipleObjects(count, handles, false, 0)
		if wait_res >= 0 && wait_res < count {
			index := wait_res
			win.FindNextChangeNotification(change_handles[index])
		} else {
			break
		}
	}
}
