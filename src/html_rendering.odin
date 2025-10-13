package main

import "core:io"
import "core:log"
import http "odin-http"
import temple "temple"

render_page :: proc(
	req: ^http.Request,
	res: ^http.Response,
	page_template: $T,
	data: $D,
	status := http.Status.OK,
	use_cache := false,
) where T ==
	temple.Compiled(D) {
	path := req.url.path
	log.infof("Rendering page %v...", path)
	if use_cache {
		set_cache_header(res)
		log.infof("Cache header set for %v.", path)
	}

	rw := http.Response_Writer{}

	// make 16kb buffer
	buf := make([]byte, 16 * 1024, context.temp_allocator)

	http.response_writer_init(&rw, res, buf)

	_, err := page_template.with(rw.w, data)
	if err != nil {
		log.errorf("Failed to write template to buffer for %v: %v", path, err)
		http.respond_with_status(res, http.Status.Internal_Server_Error)
		return
	}

	http.response_status(res, status)
	err = io.close(rw.w)
	if err != nil {
		log.errorf("Failed to close response writer for %v: %v", path, err)
	}
	log.infof("Page %v rendered successfully.", path)
}
