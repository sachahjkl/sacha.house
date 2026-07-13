package main

import "core:mem"
import "core:os"
import "core:strings"

import http "lib:odin-http"

Static_File :: struct {
	data: []u8,
}

Static_Store :: struct {
	files:     map[string]Static_File,
	allocator: mem.Allocator,
}

STATIC_ASSETS := #load_directory("static")
STATIC_ASSETS_CSS := #load_directory("static/css")
STATIC_ASSETS_JS := #load_directory("static/js")
STATIC_ASSETS_GIFS := #load_directory("static/gifs")
STATIC_ASSETS_FONTS := #load_directory("static/fonts")

static_store_add :: proc(store: ^Static_Store, prefix, name: string, data: []u8) -> mem.Allocator_Error {
	path, _ := os.replace_path_separators(name, '/', context.temp_allocator)
	full_path := path
	if prefix != "" {
		full_path = strings.concatenate({prefix, path}, context.temp_allocator)
	}
	owned_path := strings.clone(full_path, store.allocator) or_return
	store.files[owned_path] = Static_File{data = data}
	return .None
}

static_store_init :: proc(store: ^Static_Store, allocator := context.allocator) -> mem.Allocator_Error {
	store.allocator = allocator
	store.files = make(map[string]Static_File, allocator)
	for file in STATIC_ASSETS {
		if err := static_store_add(store, "", file.name, file.data); err != .None {
			static_store_destroy(store)
			return err
		}
	}
	for file in STATIC_ASSETS_CSS {
		if err := static_store_add(store, "css/", file.name, file.data); err != .None {
			static_store_destroy(store)
			return err
		}
	}
	for file in STATIC_ASSETS_JS {
		if err := static_store_add(store, "js/", file.name, file.data); err != .None {
			static_store_destroy(store)
			return err
		}
	}
	for file in STATIC_ASSETS_GIFS {
		if err := static_store_add(store, "gifs/", file.name, file.data); err != .None {
			static_store_destroy(store)
			return err
		}
	}
	for file in STATIC_ASSETS_FONTS {
		if err := static_store_add(store, "fonts/", file.name, file.data); err != .None {
			static_store_destroy(store)
			return err
		}
	}
	return .None
}

static_store_destroy :: proc(store: ^Static_Store) {
	if store == nil || store.files == nil {
		return
	}
	for path in store.files {
		delete(path, store.allocator)
	}
	delete(store.files)
	store^ = {}
}

serve_static_file :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	path := req.url_params[0]
	if file, ok := app.static.files[path]; ok {
		set_cache_header(res)
		http.respond_file_content(res, path, file.data[:])
	} else {
		http.respond_with_status(res, http.Status.Not_Found)
	}
}

