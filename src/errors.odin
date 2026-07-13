package main

import "core:fmt"

Error_Type :: enum {
	None,
	Network,
	Filesystem,
	Authorization,
	Validation,
	HTTP_Status,
	GraphQL,
	JSON_Marshal,
	JSON_Unmarshal,
	Database,
	Unknown,
}

Error :: struct {
	type: Error_Type,
	msg:  string,
	status: int,
}

error_string :: proc(e: Error) -> string {
	return fmt.tprintf("Error %v: %s", e.type, e.msg)
}
