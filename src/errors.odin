package main

import "core:fmt"

Error_Type :: enum {
	None,
	Network,
	Filesystem,
	Authorization,
	Validation,
	JSON_Marshal,
	JSON_Unmarshal,
	Database,
	Unknown,
}

Error :: struct {
	type: Error_Type,
	msg:  string,
}

error_string :: proc(e: Error) -> string {
	return fmt.tprintf("Error %v: %s", e.type, e.msg)
}
