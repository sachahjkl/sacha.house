#+feature global-context

package http

import "core:os"

@(init, private)
server_opts_init :: proc() {
	Default_Server_Opts.thread_count = os.processor_core_count()
}
