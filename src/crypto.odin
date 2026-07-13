package main

import "core:encoding/uuid"
import "core:math/rand"

generate_id :: proc(generator: ^rand.Generator, allocator := context.temp_allocator) -> string {
	context.random_generator = generator^
	uuid_val := uuid.generate_v7()
	return uuid.to_string(uuid_val, allocator = allocator)
}
