package main

import "core:io"
import "core:log"
import http "lib:odin-http"
import temple "lib:temple"

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

	headers_set_content_type_app_mime(&res.headers, .Html)

	rw:  http.Response_Writer
	buf: [128]byte
	http.response_writer_init(&rw, res, buf[:])
	defer io.close(rw.w)

	log.debugf("Content type: %v", http.headers_get(res.headers, "content-type"))

	_, err := page_template.with(rw.w, data)
	if err != nil {
		log.errorf("Failed to write template to buffer for %v: %v", path, err)
		http.respond_with_status(res, http.Status.Internal_Server_Error)
		return
	}

	http.response_status(res, status)
	
	log.infof("Page %v rendered successfully.", path)
}
