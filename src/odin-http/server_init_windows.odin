#+feature global-context

package http

import "core:os"

@(init, private)
server_opts_init :: proc() {
	// TODO: Why is it 1 ?
	Default_Server_Opts.thread_count = 1
}
