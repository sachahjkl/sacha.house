package main

import "core:fmt"
import "core:log"
import "core:sort"
import "core:strings"
import "core:time"

import http "lib:odin-http"
import temple "lib:temple"

blog_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	Page_Posts :: struct {
		using post: Post,
		dateString: string,
		timeString: string,
	}
	Year_Group :: struct {
		year:  int,
		posts: []Page_Posts,
	}
	Page_Data :: struct {
		using base: Base_Page_Data,
		YearGroups: []Year_Group,
	}

	posts, err := fetch_local_posts(&app.blog)
	if err.type != .None {
		log.errorf("could not fetch posts: %v", err)
	}
	sort.quick_sort_proc(posts, proc(a, b: Post) -> int {
		a_time, _, _ := time.iso8601_to_time_and_offset(a.publishedAt)
		b_time, _, _ := time.iso8601_to_time_and_offset(b.publishedAt)
		return int(clamp(time.time_to_unix_nano(b_time) - time.time_to_unix_nano(a_time), -1, 1))
	})

	year_groups := make([dynamic]Year_Group, context.temp_allocator)
	current_year := -1
	current_group_posts := make([dynamic]Page_Posts, context.temp_allocator)
	for post in posts {
		sort_at, _ := iso8601_to_datetime(post.publishedAt)
		year := int(get_local_year(app.timezone, sort_at))
		if current_year != -1 && year != current_year {
			append(&year_groups, Year_Group{year = current_year, posts = current_group_posts[:]})
			current_group_posts = make([dynamic]Page_Posts, context.temp_allocator)
		}
		current_year = year
		append(&current_group_posts, Page_Posts {
			post = post,
			dateString = format_date(app.timezone, sort_at),
			timeString = format_time(app.timezone, sort_at),
		})
	}
	if len(current_group_posts) > 0 {
		append(&year_groups, Year_Group{year = current_year, posts = current_group_posts[:]})
	}

	data := Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data {
				title = "blog / sacha.house",
				description = "My blog in which I will (rarely) post subjects often related to computer science.",
			},
			req.url.path,
			get_auth_level(&app.sessions, &app.config, req, res) == .Authorized,
		),
		YearGroups = year_groups[:],
	}
	page_template := temple.compiled("templates/posts.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}

blog_post_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	Page_Data :: struct {
		using base: Base_Page_Data,
		Post:       Template_Post_Detail,
	}

	post, err := fetch_local_post(&app.blog, req.url_params[0])
	if err.type != .None {
		log.errorf("could not fetch post: %v", err)
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}
	updated_at, _ := iso8601_to_datetime(post.updatedAt)
	created_at, _ := iso8601_to_datetime(post.createdAt)
	template_post := Template_Post_Detail {
		slug = post.slug,
		title = post.title,
		language = post.language,
		updatedAt = post.updatedAt,
		createdAt = post.createdAt,
		updatedOn = format_date(app.timezone, updated_at),
		updatedAtTime = format_time(app.timezone, updated_at),
		createdOn = format_date(app.timezone, created_at),
		createdAtTime = format_time(app.timezone, created_at),
		author = post.author.name,
		content = post.content,
	}
	data := Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data {
				title = fmt.tprintf("%s / sacha.house", post.title),
				description = excerpt_from_plain_text(post.content.text, 180, context.temp_allocator),
			},
			req.url.path,
			get_auth_level(&app.sessions, &app.config, req, res) == .Authorized,
			post.language,
		),
		Post = template_post,
	}
	page_template := temple.compiled("templates/post.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}

blog_rss_feed :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	posts, err := fetch_local_posts(&app.blog)
	if err.type != .None {
		log.errorf("could not fetch posts: %v", err)
		http.respond_with_status(res, http.Status.Internal_Server_Error)
		return
	}
	sort.quick_sort_proc(posts, proc(a, b: Post) -> int {
		a_time, _, _ := time.iso8601_to_time_and_offset(a.publishedAt)
		b_time, _, _ := time.iso8601_to_time_and_offset(b.publishedAt)
		return int(clamp(time.time_to_unix_nano(b_time) - time.time_to_unix_nano(a_time), -1, 1))
	})

	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n")
	strings.write_string(&sb, "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n")
	strings.write_string(&sb, "\t<channel>\n")
	strings.write_string(&sb, "\t\t<title>sacha.house blog</title>\n")
	strings.write_string(&sb, "\t\t<link>https://sacha.house/blog</link>\n")
	strings.write_string(&sb, fmt.tprintf("\t\t<description>%s's personal blog.</description>\n", app.me.fullName))
	strings.write_string(&sb, "\t\t<atom:link href=\"https://sacha.house/blog/feed.xml\" rel=\"self\" type=\"application/rss+xml\" />\n")
	strings.write_string(&sb, "\t\t<language>en-us</language>\n")
	if len(posts) > 0 {
		latest, _, _ := time.iso8601_to_time_and_offset(posts[0].publishedAt)
		strings.write_string(&sb, fmt.tprintf("\t\t<lastBuildDate>%s</lastBuildDate>\n", format_rfc1123(latest, context.temp_allocator)))
	}
	for post in posts {
		strings.write_string(&sb, "\t\t<item>\n")
		strings.write_string(&sb, fmt.tprintf("\t\t\t<title>%s</title>\n", xml_escape(post.title, context.temp_allocator)))
		link := fmt.tprintf("https://sacha.house/blog/%s", post.slug)
		strings.write_string(&sb, fmt.tprintf("\t\t\t<link>%s</link>\n", link))
		strings.write_string(&sb, fmt.tprintf("\t\t\t<guid>%s</guid>\n", link))
		published, _, _ := time.iso8601_to_time_and_offset(post.publishedAt)
		strings.write_string(&sb, fmt.tprintf("\t\t\t<pubDate>%s</pubDate>\n", format_rfc1123(published, context.temp_allocator)))
		if post.author.name != "" {
			strings.write_string(&sb, fmt.tprintf("\t\t\t<author>%s</author>\n", xml_escape(post.author.name, context.temp_allocator)))
		}
		strings.write_string(&sb, "\t\t</item>\n")
	}
	strings.write_string(&sb, "\t</channel>\n")
	strings.write_string(&sb, "</rss>")
	headers_set_content_type_app_mime(&res.headers, .Rss)
	set_cache_header(res, "public, max-age=600")
	http.body_set_str(res, strings.to_string(sb))
	http.respond(res, http.Status.OK)
}

blog_atom_feed :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	posts, err := fetch_local_posts(&app.blog)
	if err.type != .None {
		log.errorf("could not fetch posts: %v", err)
		http.respond_with_status(res, http.Status.Internal_Server_Error)
		return
	}
	sort.quick_sort_proc(posts, proc(a, b: Post) -> int {
		a_time, _, _ := time.iso8601_to_time_and_offset(a.publishedAt)
		b_time, _, _ := time.iso8601_to_time_and_offset(b.publishedAt)
		return int(clamp(time.time_to_unix_nano(b_time) - time.time_to_unix_nano(a_time), -1, 1))
	})

	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
	strings.write_string(&sb, "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n")
	strings.write_string(&sb, "\t<title>sacha.house blog</title>\n")
	strings.write_string(&sb, fmt.tprintf("\t<subtitle>%s's personal blog</subtitle>\n", app.me.fullName))
	strings.write_string(&sb, "\t<link href=\"https://sacha.house/blog\"/>\n")
	strings.write_string(&sb, "\t<link href=\"https://sacha.house/blog/atom.xml\" rel=\"self\"/>\n")
	if len(posts) > 0 {
		strings.write_string(&sb, fmt.tprintf("\t<updated>%s</updated>\n", posts[0].publishedAt))
	}
	strings.write_string(&sb, "\t<author>\n")
	strings.write_string(&sb, fmt.tprintf("\t\t<name>%s</name>\n", app.me.fullName))
	strings.write_string(&sb, fmt.tprintf("\t\t<email>%s</email>\n", app.me.mail))
	strings.write_string(&sb, "\t</author>\n")
	strings.write_string(&sb, "\t<id>https://sacha.house/blog</id>\n")
	for post in posts {
		strings.write_string(&sb, "\t<entry>\n")
		strings.write_string(&sb, fmt.tprintf("\t\t<title>%s</title>\n", xml_escape(post.title, context.temp_allocator)))
		link := fmt.tprintf("https://sacha.house/blog/%s", post.slug)
		strings.write_string(&sb, fmt.tprintf("\t\t<link href=\"%s\"/>\n", link))
		strings.write_string(&sb, fmt.tprintf("\t\t<id>%s</id>\n", link))
		strings.write_string(&sb, fmt.tprintf("\t\t<updated>%s</updated>\n", post.publishedAt))
		if post.author.name != "" {
			strings.write_string(&sb, "\t\t<author>\n")
			strings.write_string(&sb, fmt.tprintf("\t\t\t<name>%s</name>\n", xml_escape(post.author.name, context.temp_allocator)))
			strings.write_string(&sb, "\t\t</author>\n")
		}
		strings.write_string(&sb, "\t</entry>\n")
	}
	strings.write_string(&sb, "</feed>")
	headers_set_content_type_app_mime(&res.headers, .Atom)
	set_cache_header(res, "public, max-age=600")
	http.body_set_str(res, strings.to_string(sb))
	http.respond(res, http.Status.OK)
}
