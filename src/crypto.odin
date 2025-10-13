package main

import "core:crypto"
import "core:encoding/uuid"
import "core:math/rand"

init_random_generator :: proc() {
	random_generator = crypto.random_generator()
}

get_random_generator :: proc() -> rand.Generator {
	return random_generator
}

generate_id :: proc(allocator := context.temp_allocator) -> string {
	context.random_generator = random_generator
	uuid_val := uuid.generate_v7()
	uuid_str := uuid.to_string(uuid_val, allocator = allocator)
	return uuid_str
}

@(private)
random_generator: rand.Generator
