package main

import http "lib:odin-http"

App_Mime_Types :: union {
	http.Mime_Type,
	Extended_Mime_Types,
}

Extended_Mime_Types :: enum {
	Atom,
	Rss,
}

@(private = "file")
_extended_mime_to_content_type := [Extended_Mime_Types]string {
	.Atom = "application/atom+xml",
	.Rss  = "application/rss+xml",
}


headers_set_content_type_app_mime :: proc(headers: ^http.Headers, m: App_Mime_Types) {
	if mime := app_mime_to_content_type_string(m); mime != nil {
		http.headers_set_content_type_string(headers, mime.(string))
	}
}

app_mime_to_content_type_string :: proc(m: App_Mime_Types) -> Maybe(string) {
	switch m in m {
	case http.Mime_Type:
		return http.mime_to_content_type(m)
	case Extended_Mime_Types:
		return _extended_mime_to_content_type[m]
	}
	return nil
}
