# \[DRAFT\]

Cloudflare outage because of `.unwrap()` (lmao) : [https://blog.cloudflare.com/18-november-2025-outage/](https://blog.cloudflare.com/18-november-2025-outage/ "https://blog.cloudflare.com/18-november-2025-outage/")

![shapes at 25-11-21 14.52.47.jpg](/media/blog/rust-rewrite-xmaybex/assets/cmi8x8pfr1t9j07w5vrc5gen8-1.jpg)

looking at various rust libs that look interesting:

[https://hyper.rs/](https://hyper.rs/ "https://hyper.rs/") / [https://github.com/hyperium/hyper](https://github.com/hyperium/hyper "https://github.com/hyperium/hyper") (fast http lib, base layer of warp)

[https://crates.io/crates/warp](https://crates.io/crates/warp "https://crates.io/crates/warp") (speedy web server framework ?)

[https://crates.io/crates/include\_dir](https://crates.io/crates/include_dir "https://crates.io/crates/include_dir") (!important for self-contained, one click start, native and portable website executable)

### Handlebars for template :

[https://handlebarsjs.com/guide/expressions.html](https://handlebarsjs.com/guide/expressions.html "https://handlebarsjs.com/guide/expressions.html")

[https://crates.io/crates/handlebars](https://crates.io/crates/handlebars "https://crates.io/crates/handlebars")

### Svelte/Runed

[https://runed.dev/docs](https://runed.dev/docs "https://runed.dev/docs")

svelte project init : `bun create vite --template svelte-ts`

we'll do something with : [https://github.com/huntabyte/shadcn-svelte](https://github.com/huntabyte/shadcn-svelte "https://github.com/huntabyte/shadcn-svelte")

[https://developer.mozilla.org/en-US/docs/Web/API/EventSource](https://developer.mozilla.org/en-US/docs/Web/API/EventSource "https://developer.mozilla.org/en-US/docs/Web/API/EventSource")

Event source playground : [https://svelte.dev/playground/67f416aa070148d6933bf4242c674565?version=5.43.14](https://svelte.dev/playground/67f416aa070148d6933bf4242c674565?version=5.43.14 "https://svelte.dev/playground/67f416aa070148d6933bf4242c674565?version=5.43.14")

### Rust Application Server

warp rate limit : [https://docs.rs/warp-rate-limit/latest/warp\_rate\_limit/](https://docs.rs/warp-rate-limit/latest/warp_rate_limit/ "https://docs.rs/warp-rate-limit/latest/warp_rate_limit/")

sse keep\_alive : [https://docs.rs/warp/latest/warp/filters/sse/fn.keep\_alive.html](https://docs.rs/warp/latest/warp/filters/sse/fn.keep_alive.html "https://docs.rs/warp/latest/warp/filters/sse/fn.keep_alive.html")
