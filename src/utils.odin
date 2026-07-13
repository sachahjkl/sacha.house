package main

import "core:crypto"
import "core:fmt"
import "core:math/rand"
import "core:strings"

import http "lib:odin-http"


capitalize :: proc(s: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf(
		"%s%s",
		strings.to_upper(s[:1], context.temp_allocator),
		s[1:],
		allocator = allocator,
	)
}
/*
NOTE(sachahjkl):
- This function is used to set the Cache-Control header on the response.
- The default value is "public, max-age=86400" which is 1 day.
*/
set_cache_header :: proc(res: ^http.Response, value := "public, max-age=86400") {
	http.headers_set(&res.headers, "Cache-Control", value)
}

CHARS :: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@"

/*
NOTE(sachahjkl):
- Uses crypto.rand_bytes so output is always from the character set (no broken Unicode).
- Rejection sampling avoids modulo bias; only indices in [0, len(choices)) are used.
*/
generate_random_string :: proc(
	n: int = 15,
	choices: string = CHARS,
	allocator := context.allocator,
) -> string {
	if len(choices) == 0 || n <= 0 {
		return ""
	}

	N := len(choices)
	// Rejection sampling: accept bytes in [0, cap) so that b % N is uniform.
	cap := 256 - (256 % N) // e.g. N=36 -> cap=252

	builder := strings.Builder{}
	strings.builder_init(&builder, allocator)
	defer strings.builder_destroy(&builder)

	// Scratch buffer for random bytes; refill as needed until we have n accepted.
	buf: [32]u8
	written: int
	for written < n {
		crypto.rand_bytes(buf[:])
		for b in buf {
			if written >= n do break
			if b < u8(cap) {
				strings.write_byte(&builder, choices[int(b) % N])
				written += 1
			}
		}
	}

	return strings.to_string(builder)
}

generate_random_hsl_string :: proc(generator: rand.Generator, allocator := context.allocator) -> string {
	hue := rand.int31_max(360, generator)
	sat_max: i32 = 100
	sat_min: i32 = 70
	light_max: i32 = 60
	light_min: i32 = 40
	saturation := rand.int31_max(sat_max - sat_min, generator) + sat_min
	lightness := rand.int31_max(light_max - light_min, generator) + light_min
	return fmt.aprintf("hsl(%d, %d%%, %d%%)", hue, saturation, lightness, allocator = allocator)
}

xml_escape :: proc(s: string, allocator := context.allocator) -> string {
	res, _ := strings.replace_all(s, "&", "&amp;", allocator)
	res, _ = strings.replace_all(res, "<", "&lt;", allocator)
	res, _ = strings.replace_all(res, ">", "&gt;", allocator)
	res, _ = strings.replace_all(res, "\"", "&quot;", allocator)
	res, _ = strings.replace_all(res, "'", "&apos;", allocator)
	return res
}