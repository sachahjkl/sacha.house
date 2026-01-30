package main

import "core:path/filepath"
import "core:strings"

import http "lib:odin-http"

Static_File :: struct {
	data:      []u8,
	mime_type: string,
}

static_files: map[string]Static_File

STATIC_ASSETS := #load_directory("static")
STATIC_ASSETS_CSS := #load_directory("static/css")
STATIC_ASSETS_JS := #load_directory("static/js")
STATIC_ASSETS_GIFS := #load_directory("static/gifs")
STATIC_ASSETS_FONTS := #load_directory("static/fonts")
STATIC_ASSETS_SHARE := #load_directory("static/share")

init_static_files :: proc() {
	static_files = make(map[string]Static_File, context.allocator)
	for file in STATIC_ASSETS {
		path, _ := filepath.to_slash(file.name)
		mime_type := get_mime_type(path)
		static_files[path] = Static_File{file.data, mime_type}
	}
	css_prefix :: "css/"
	for file in STATIC_ASSETS_CSS {
		path, _ := filepath.to_slash(file.name)
		full_path := strings.concatenate({css_prefix, path})
		defer delete(full_path)
		mime_type := get_mime_type(full_path)
		static_files[strings.clone(full_path)] = Static_File{file.data, mime_type}
	}
	js_prefix :: "js/"
	for file in STATIC_ASSETS_JS {
		path, _ := filepath.to_slash(file.name)
		full_path := strings.concatenate({js_prefix, path})
		defer delete(full_path)
		mime_type := get_mime_type(full_path)
		static_files[strings.clone(full_path)] = Static_File{file.data, mime_type}
	}
	gifs_prefix :: "gifs/"
	for file in STATIC_ASSETS_GIFS {
		path, _ := filepath.to_slash(file.name)
		full_path := strings.concatenate({gifs_prefix, path})
		defer delete(full_path)
		mime_type := get_mime_type(full_path)
		static_files[strings.clone(full_path)] = Static_File{file.data, mime_type}
	}
	fonts_prefix :: "fonts/"
	for file in STATIC_ASSETS_FONTS {
		path, _ := filepath.to_slash(file.name)
		full_path := strings.concatenate({fonts_prefix, path})
		defer delete(full_path)
		mime_type := get_mime_type(full_path)
		static_files[strings.clone(full_path)] = Static_File{file.data, mime_type}
	}
	share_prefix :: "share/"
	for file in STATIC_ASSETS_SHARE {
		path, _ := filepath.to_slash(file.name)
		full_path := strings.concatenate({share_prefix, path})
		defer delete(full_path)
		mime_type := get_mime_type(full_path)
		static_files[strings.clone(full_path)] = Static_File{file.data[:], mime_type}
	}
}

serve_static_file :: proc(req: ^http.Request, res: ^http.Response) {
	path := req.url_params[0]
	if file, ok := static_files[path]; ok {
		set_cache_header(res)
		http.respond_file_content(res, path, file.data[:])
	} else {
		http.respond_with_status(res, http.Status.Not_Found)
	}
}

get_mime_type :: proc(path: string) -> string {
	ext := filepath.ext(path)
	switch ext {
	case ".html":
		return "text/html"
	case ".gpg":
		return "application/pgp-keys"
	case ".css":
		return "text/css"
	case ".js":
		return "application/javascript"
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".gif":
		return "image/gif"
	case ".svg":
		return "image/svg+xml"
	case ".ico":
		return "image/x-icon"
	case ".webmanifest":
		return "application/manifest+json"
	case ".xml":
		return "application/xml"
	case ".pdf":
		return "application/pdf"
	case ".ttf":
		return "font/ttf"
	case ".exe":
		return "application/octet-stream"
	case:
		return "text/plain"
	}
}
