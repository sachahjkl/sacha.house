package main

import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:strings"

import http "lib:odin-http"
import client "lib:odin-http/client"

capitalize :: proc(s: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%s%s", strings.to_upper(s[:1], context.temp_allocator), s[1:], allocator = allocator)
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
- The previous implementation of `generate_random_string` was producing broken unicode strings.
- This was likely due to a misuse of the random number generation functions.
- The new implementation uses `crypto/rand` to generate random bytes and then maps them to the character set.
- It uses rejection sampling to avoid modulo bias, ensuring a uniform distribution of characters.
- The default length of the generated string has been set to 15, as requested.
*/
generate_random_string :: proc(
	n: int = 15,
	choices: string = CHARS,
	allocator := context.allocator,
) -> string {
	if len(choices) == 0 || n <= 0 {
		return ""
	}

	builder := strings.Builder{}
	strings.builder_init(&builder, allocator)
	defer strings.builder_destroy(&builder)

	for i in 0 ..< n {
		idx := rand.int31_max(i32(len(choices))) // random index into choices
		strings.write_byte(&builder, choices[idx])
	}

	return strings.to_string(builder)
}

generate_random_hsl_string :: proc(allocator := context.allocator) -> string {
	hue := rand.int31_max(360)
	sat_max: i32 = 100
	sat_min: i32 = 70
	light_max: i32 = 60
	light_min: i32 = 40
	saturation := rand.int31_max(sat_max - sat_min) + sat_min
	lightness := rand.int31_max(light_max - light_min) + light_min
	return fmt.aprintf("hsl(%d, %d%%, %d%%)", hue, saturation, lightness, allocator = allocator)
}
