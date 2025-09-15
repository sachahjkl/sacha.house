package main

import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:net"
import "core:sort"
import "core:strings"
import "core:time"
import http "odin-http"
import client "odin-http/client"
import temple "temple"


// NOTE(Sacha Froment):
// the http framework cleans up the `` context.temp_allocator``  at the end of each request
// so we don't need to manually clean it up here.
// This means we SHOULD USE it instead of context.allocator for values that only live for the duration of the request.
server_start :: proc() {

	s: http.Server
	http.server_shutdown_on_interrupt(&s)

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)
	log.info("Initializing routes...")

	http.route_get(&router, "/static/(.*)", http.handler(serve_static_file))
	http.route_get(&router, "/", http.handler(index_page))
	http.route_get(&router, "/ping", http.handler(ping))
	http.route_get(&router, "/blog", http.handler(blog_page))
	// slug of shape : word-... (lowercase) and all words separated by a dash
	http.route_get(&router, "/blog/([%w-]+)", http.handler(blog_post_page))
	http.route_get(&router, "/about", http.handler(about_page))
	http.route_get(&router, "/projects", http.handler(projects_page))
	http.route_get(&router, "/ip", http.handler(ip_page))
	http.route_get(&router, "/api/ip", http.handler(ip_api))
	http.route_get(&router, "/mariage", http.handler(mariage_redirect))
	http.route_get(&router, "/teapot", http.handler(teapot_page))
	http.route_get(&router, "/admin", http.handler(admin_page))

	// fallback to static serve but from the root
	http.route_get(&router, "/(.*)", http.handler(serve_static_file))

	log.info("Routes initialized.")


	routed := http.router_handler(&router)

	listen_endpoint := net.Endpoint {
		address = net.IP4_Any,
		port    = 6969,
	}

	log.infof("Listening on http://%s", net.endpoint_to_string(listen_endpoint))

	if init_cache() != nil {
		log.error("Failed to initialize cache")
		return
	}

	log.info("Cache initialized.")

	defer cleanup_cache()

	err := http.listen_and_serve(&s, routed, listen_endpoint)
	fmt.assertf(err == nil, "server stopped with error: %v", err)
}

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

	rw := http.Response_Writer{}

	// make 16kb buffer
	buf := make([]byte, 16 * 1024, context.temp_allocator)

	http.response_writer_init(&rw, res, buf)

	_, err := page_template.with(rw.w, data)
	if err != nil {
		log.errorf("Failed to write template to buffer for %v: %v", path, err)
		http.respond_with_status(res, http.Status.Internal_Server_Error)
		return
	}

	http.response_status(res, status)
	err = io.close(rw.w)
	if err != nil {
		log.errorf("Failed to close response writer for %v: %v", path, err)
	}
	log.infof("Page %v rendered successfully.", path)
}

index_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	Page_Data :: struct {
		using base: Base_Page_Data,
		Mail:       string,
		GpgPrint:   string,
	}

	data := Page_Data {
		base     = create_base_page_data(
			Maybe_SEO_Data {
				title = "home / sacha.house",
				description = "Sacha Froment's personal website.",
			},
			req.url.path,
			is_authorized(req),
		),
		Mail     = ME.mail,
		GpgPrint = ME.gpgPrint,
	}

	page_template := temple.compiled("templates/index.temple.twig", Page_Data)

	render_page(req, res, page_template, data)
}

about_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	Page_Data :: struct {
		using base:          Base_Page_Data,
		Prenom:              string,
		Age:                 int,
		PlaceOfLiving:       string,
		CurriculumVitae:     string,
		Mail:                string,
		EthAddress:          string,
		MoneroAddress:       string,
		GpgPrint:            string,
		Linkedin:            string,
		Github:              string,
		Gitlab:              string,
		LinkedInExperiences: []Template_Experience,
		LinkedInEducation:   []Template_Education,
	}
	page_template := temple.compiled("templates/about.temple.twig", Page_Data)

	profile, err := get_gist_profile()
	log.infof("Fetched gist profile")

	if err.type != .None {
		// Silently fail, the template will show nothing.
	}

	template_experiences := make(
		[]Template_Experience,
		len(profile.experiences),
		context.temp_allocator,
	)
	for exp, i in profile.experiences {
		template_experiences[i] = Template_Experience {
			title                        = exp.title,
			company                      = exp.company,
			location                     = exp.location,
			starts_at                    = format_linkedin_date(exp.starts_at),
			ends_at                      = format_linkedin_date(exp.ends_at),
			description                  = exp.description,
			company_linkedin_profile_url = exp.company_linkedin_profile_url,
		}
	}

	template_education := make(
		[]Template_Education,
		len(profile.education),
		context.temp_allocator,
	)
	for edu, i in profile.education {
		edu_title := fmt.tprintf("%s in %s", edu.degree_name, edu.field_of_study)
		template_education[i] = Template_Education {
			school                      = edu.school,
			degree_name                 = edu.degree_name,
			field_of_study              = edu.field_of_study,
			starts_at                   = format_linkedin_date(edu.starts_at),
			ends_at                     = format_linkedin_date(edu.ends_at),
			description                 = edu.description,
			school_linkedin_profile_url = edu.school_linkedin_profile_url,
			title                       = edu_title,
		}
	}

	data := Page_Data {
		base                = create_base_page_data(
			Maybe_SEO_Data {
				title = "about / sacha.house",
				description = fmt.tprintf(
					"Presentation of %s %s. You can find my contact details, my CV and a brief presentation of who I am.",
					ME.prenom,
					ME.nom,
				),
			},
			req.url.path,
			is_authorized(req),
		),
		Prenom              = capitalize(ME.prenom),
		Age                 = ME.age,
		PlaceOfLiving       = ME.placeOfLiving,
		CurriculumVitae     = ME.curriculumVitae,
		Mail                = ME.mail,
		EthAddress          = ME.ethAddress,
		MoneroAddress       = ME.moneroAdress,
		GpgPrint            = ME.gpgPrint,
		Linkedin            = ME.linkedin,
		Github              = ME.github,
		Gitlab              = ME.gitlab,
		LinkedInExperiences = template_experiences,
		LinkedInEducation   = template_education,
	}

	render_page(req, res, page_template, data)

}

ping :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	http.respond_plain(res, "pong")
}

blog_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)

	Page_Posts :: struct {
		using post: Post,
		dateString: string,
		timeString: string,
	}

	Page_Data :: struct {
		using base: Base_Page_Data,
		Posts:      []Page_Posts,
	}
	page_template := temple.compiled("templates/posts.temple.twig", Page_Data)

	posts, err := fetch_posts()
	if err.type != .None {
		log.errorf("could not fetch posts: %v", err)
	}

	// trie les posts du plus récent au plus ancien
	sort.quick_sort_proc(
		posts,
		proc(a, b: Post) -> int {
			// parse dates and compare timestamps
			updatedAtA, offsetA, _ := time.iso8601_to_time_and_offset(a.updatedAt)
			updatedAtB, offsetB, _ := time.iso8601_to_time_and_offset(b.updatedAt)


			return int(
				clamp(
					time.time_to_unix_nano(updatedAtB) - time.time_to_unix_nano(updatedAtA),
					-1,
					1,
				),
			)
		},
	)

	// NOTE(sachahjkl):
	// use the context.temp_allocator, the values are only used for the duration of the request
	template_posts := make([]Page_Posts, len(posts), context.temp_allocator)
	for post, i in posts {
		template_posts[i] = Page_Posts {
			post = post,
		}

		updatedAt, _ := iso8601_to_datetime(post.updatedAt)
		template_posts[i].dateString = format_date(updatedAt)
		template_posts[i].timeString = format_time(updatedAt)
	}

	data := Page_Data {
		base  = create_base_page_data(
			Maybe_SEO_Data {
				title = "blog / sacha.house",
				description = "My blog in which I will (rarely) post subjects often related to computer science.",
			},
			req.url.path,
			is_authorized(req),
		),
		Posts = template_posts,
	}

	render_page(req, res, page_template, data)
}

blog_post_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	Page_Data :: struct {
		using base: Base_Page_Data,
		Post:       Template_Post_Detail,
	}
	page_template := temple.compiled("templates/post.temple.twig", Page_Data)

	slug := req.url_params[0]
	post, err := fetch_post(slug)
	if err.type != .None {
		log.errorf("could not fetch post: %v", err)
		http.respond_with_status(res, http.Status.Not_Found)
		return
	}

	updatedAt, _ := iso8601_to_datetime(post.updatedAt)
	createdAt, _ := iso8601_to_datetime(post.createdAt)


	template_post := Template_Post_Detail {
		slug          = post.slug,
		title         = post.title,
		updatedAt     = post.updatedAt,
		createdAt     = post.createdAt,
		updatedOn     = format_date(updatedAt),
		updatedAtTime = format_time(updatedAt),
		createdOn     = format_date(createdAt),
		createdAtTime = format_time(createdAt),
		content       = post.content,
	}

	data := Page_Data {
		base = create_base_page_data(
			Maybe_SEO_Data {
				title = fmt.tprintf("%s / sacha.house", post.title),
				description = string(post.content.text[:160]),
			},
			req.url.path,
			is_authorized(req),
		),
		Post = template_post,
	}

	render_page(req, res, page_template, data)

}

teapot_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	Brew_Message :: struct {
		text:  string,
		emoji: string,
	}
	Page_Data :: struct {
		using base:  Base_Page_Data,
		Spewage:     string,
		BrewMessage: Brew_Message,
		IsATeapot:   bool,
	}
	page_template := temple.compiled("templates/teapot.temple.twig", Page_Data)

	next_spewage := generate_random_string(5, "abcdefghijklmnopqrstuvwxyz1234567890")
	brew_message := Brew_Message{}

	status := http.Status.OK
	is_a_teapot := false

	if drink, ok := http.query_get_percent_decoded(req.url, "drink"); ok {
		switch drink {
		case "tea":
			brew_message = Brew_Message {
				text  = "Here is your tea!",
				emoji = "🍵",
			}
		case "coffee":
			{
				status = http.Status.Im_A_Teapot
				is_a_teapot = true
				brew_message = Brew_Message {
					text = "Did you really think a teapot could brew you coffee ??\nare you some kind of lunatic or something ?",
				}
			}
		case:
			brew_message = Brew_Message {
				text  = fmt.tprintf("What kind of a drink is \"%s\" ???", drink),
				emoji = "🤮",
			}
		}
	}

	data := Page_Data {
		base        = create_base_page_data(
			Maybe_SEO_Data{title = "teapot / sacha.house", description = "I'm a teapot."},
			req.url.path,
			is_authorized(req),
		),
		Spewage     = next_spewage,
		BrewMessage = brew_message,
		IsATeapot   = is_a_teapot,
	}

	render_page(req, res, page_template, data, status)
}

ip_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	ip_api(req, res)
}

projects_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	Page_Data :: struct {
		using base:     Base_Page_Data,
		Username:       string,
		HayekFR:        string,
		HayekFRRepo:    string,
		Dotfiles:       string,
		GitLabProjects: []Template_Project,
		GitHubProjects: []Template_Project,
	}
	page_template := temple.compiled("templates/projects.temple.twig", Page_Data)

	now := time.now()
	duration := duration_between(projects_cache.last_fetched, now)

	if projects_cache.last_fetched != {} && time.duration_minutes(duration) < 5 {
		log.info("Serving projects from cache.")
	} else {
		reset_project_cache()

		log.info("Fetching fresh projects, cache expired or empty.")
		gitlab_projects_raw, gitlab_err := gitlab_projects_api()
		if gitlab_err.type != .None {
			log.errorf("could not get gitlab projects: %v", gitlab_err)
		}
		github_projects_raw, github_err := github_projects_api()
		if github_err.type != .None {
			log.errorf("could not get github projects: %v", github_err)
		}

		// NOTE(sachahjkl):
		// use the context.allocator instead of context.temp_allocator here
		// because the values are cached and will be used later
		projects_cache.gitlab = make(
			[]Template_Project,
			len(gitlab_projects_raw),
			projects_cache.allocator,
		)

		for project, i in gitlab_projects_raw {
			first_letter :=
				strings.to_upper(project.name[:1], projects_cache.allocator) if len(project.name) > 0 else ""
			projects_cache.gitlab[i] = Template_Project {
				name            = strings.clone(project.name, projects_cache.allocator),
				url             = strings.clone(project.url, projects_cache.allocator),
				descriptionHtml = strings.clone(project.descriptionHtml, projects_cache.allocator),
				avatarUrl       = strings.clone(project.avatarUrl, projects_cache.allocator),
				first_letter    = first_letter,
				hslColor        = generate_random_hsl_string(projects_cache.allocator),
				hasAvatar       = strings.clone(project.avatarUrl, projects_cache.allocator) != "",
			}
		}

		// NOTE(sachahjkl):
		// use the context.allocator instead of context.temp_allocator here
		// because the values are cached and will be used later
		projects_cache.github = make(
			[]Template_Project,
			len(github_projects_raw),
			projects_cache.allocator,
		)
		for project, i in github_projects_raw {
			first_letter :=
				strings.to_upper(project.name[:1], projects_cache.allocator) if len(project.name) > 0 else ""
			projects_cache.github[i] = Template_Project {
				name            = strings.clone(project.name, projects_cache.allocator),
				url             = strings.clone(project.url, projects_cache.allocator),
				descriptionHtml = strings.clone(project.descriptionHtml, projects_cache.allocator),
				avatarUrl       = strings.clone(project.owner.avatarUrl, projects_cache.allocator),
				first_letter    = first_letter,
				hslColor        = generate_random_hsl_string(projects_cache.allocator),
				hasAvatar       = strings.clone(
					project.owner.avatarUrl,
					projects_cache.allocator,
				) != "",
			}
		}
		projects_cache.last_fetched = now
	}


	data := Page_Data {
		base           = create_base_page_data(
			Maybe_SEO_Data {
				title = "projects / sacha.house",
				description = "My personal projects.",
			},
			req.url.path,
			is_authorized(req),
		),
		Username       = ME.username,
		HayekFR        = ME.hayekfr,
		HayekFRRepo    = ME.hayekfrRepo,
		Dotfiles       = ME.dotfiles,
		GitLabProjects = projects_cache.gitlab,
		GitHubProjects = projects_cache.github,
	}

	render_page(req, res, page_template, data)

}

admin_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	if !is_authorized(req) {
		http.respond_with_status(res, http.Status.Unauthorized)
		return
	}

	Page_Data :: struct {
		using base:    Base_Page_Data,
		IpAddress:     string,
		CreditBalance: int,
		ProfileData:   string,
	}
	page_template := temple.compiled("templates/admin.temple.twig", Page_Data)

	// ProxyCurl is dead, we'll keep the balance at 0 and show it for historical purposes
	balance := 0

	profile_json := ""
	if profile_json_str := get_gist_profile_string(); profile_json_str != nil {
		profile_json = profile_json_str.(string)
	}


	data := Page_Data {
		base          = create_base_page_data(
			Maybe_SEO_Data{title = "admin / sacha.house", description = "Admin panel."},
			req.url.path,
			is_authorized(req),
		),
		IpAddress     = net.address_to_string(req.client.address),
		CreditBalance = balance,
		ProfileData   = profile_json,
	}

	render_page(req, res, page_template, data)
}

ip_api :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	ip_str := net.address_to_string(req.client.address)
	http.respond_plain(res, ip_str)
}

mariage_redirect :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	http.headers_set(&res.headers, "Location", "/static/Patricia_et_Sacha_Invitation.pdf")
	http.respond(res, http.Status.Found)
}

Template_Project :: struct {
	name:            string,
	url:             string,
	descriptionHtml: string,
	avatarUrl:       string,
	first_letter:    string,
	hslColor:        string,
	hasAvatar:       bool,
}

fetch_posts :: proc() -> (posts: []Post, err: Error) {
	req_body: GraphQL_Request
	req_body.query =
	`
		query GET_POSTS {
			posts(orderBy: publishedAt_ASC, stage: PUBLISHED) {
				slug
				title
				updatedAt
			}
		}
	`


	client_req: client.Request
	client.request_init(&client_req, .Post)
	defer client.request_destroy(&client_req)

	if err_json := client.with_json(&client_req, req_body); err_json != nil {
		msg := fmt.tprintf("JSON error: %s", err_json)
		log.error(msg)
		return nil, Error{type = .JSON_Marshal, msg = msg}
	}

	client_res, err_req := client.request(&client_req, APP_CONFIG.HYGRAPH_API_ENDPOINT)
	if err_req != nil {
		msg := fmt.tprintf("Request failed: %s", err_req)
		log.error(msg)
		return nil, Error{type = .Network, msg = msg}
	}
	defer client.response_destroy(&client_res)

	body, allocation, berr := client.response_body(&client_res)
	if berr != nil {
		msg := fmt.tprintf("Error retrieving response body: %s", berr)
		log.error(msg)
		return nil, Error{type = .Network, msg = msg}
	}
	defer client.body_destroy(body, allocation)

	body_bytes, ok := body.(client.Body_Plain)
	if !ok {
		msg := "Error converting body to bytes"
		log.error(msg)
		return nil, Error{type = .Validation, msg = msg}
	}

	posts_res: Posts_Response
	unmarshal_err := json.unmarshal(
		transmute([]u8)body_bytes,
		&posts_res,
		allocator = context.temp_allocator,
	)
	if unmarshal_err != nil {
		msg := fmt.tprintf("Error unmarshalling posts from Hygraph: %s", unmarshal_err)
		log.error(msg)
		return nil, Error{type = .JSON_Unmarshal, msg = msg}
	}

	return posts_res.data.posts, Error{type = .None}
}

fetch_post :: proc(slug: string) -> (post: Post_Detail, err: Error) {
	req_body: GraphQL_Request
	req_body.query =
	`
		query GET_POST($slug: String!) {
			post(where: { slug: $slug }) {
				slug
				title
				updatedAt
				createdAt
				content {
					html
					text
				}
			}
		}
	`


	req_body.variables = make(map[string]string, context.temp_allocator)
	req_body.variables["slug"] = slug

	client_req: client.Request
	client.request_init(&client_req, .Post)
	defer client.request_destroy(&client_req)

	if err_json := client.with_json(&client_req, req_body); err_json != nil {
		msg := fmt.tprintf("JSON error: %s", err_json)
		log.error(msg)
		return Post_Detail{}, Error{type = .JSON_Marshal, msg = msg}
	}

	client_res, err_req := client.request(&client_req, APP_CONFIG.HYGRAPH_API_ENDPOINT)
	if err_req != nil {
		msg := fmt.tprintf("Request failed: %s", err_req)
		log.error(msg)
		return Post_Detail{}, Error{type = .Network, msg = msg}
	}
	defer client.response_destroy(&client_res)

	body, allocation, berr := client.response_body(&client_res)
	if berr != nil {
		msg := fmt.tprintf("Error retrieving response body: %s", berr)
		log.error(msg)
		return Post_Detail{}, Error{type = .Network, msg = msg}
	}
	defer client.body_destroy(body, allocation)

	body_bytes, ok := body.(client.Body_Plain)
	if !ok {
		msg := "Error converting body to bytes"
		log.error(msg)
		return Post_Detail{}, Error{type = .Validation, msg = msg}
	}

	post_res: Post_Response
	unmarshal_err := json.unmarshal(
		transmute([]u8)body_bytes,
		&post_res,
		allocator = context.temp_allocator,
	)
	if unmarshal_err != nil {
		msg := fmt.tprintf("Error unmarshalling post from Hygraph: %s", unmarshal_err)
		log.error(msg)
		return Post_Detail{}, Error{type = .JSON_Unmarshal, msg = msg}
	}

	return post_res.data.post, Error{type = .None}
}

MONTH_NAMES :: [?]string {
	"",
	"Jan",
	"Feb",
	"Mar",
	"Apr",
	"May",
	"Jun",
	"Jul",
	"Aug",
	"Sep",
	"Oct",
	"Nov",
	"Dec",
}

format_linkedin_date :: proc(day: Linkedin_Day) -> string {
	if day.year == 0 {
		return "Present"
	}
	months := MONTH_NAMES
	return fmt.tprintf("%s %d", months[day.month], day.year)
}


// Projects cache

init_cache :: proc() -> mem.Allocator_Error {
	init_projects_cache() or_return
	return nil
}

cleanup_cache :: proc() {
	cleanup_projects_cache()
}

Projects_Cache :: struct {
	gitlab:       []Template_Project,
	github:       []Template_Project,
	last_fetched: time.Time,
	arena:        virtual.Arena,
	allocator:    mem.Allocator,
}


projects_cache: Projects_Cache

init_projects_cache :: proc() -> mem.Allocator_Error {
	virtual.arena_init_growing(&projects_cache.arena) or_return
	projects_cache.allocator = virtual.arena_allocator(&projects_cache.arena)
	return nil
}


reset_project_cache :: proc() {
	virtual.arena_free_all(&projects_cache.arena)

}

cleanup_projects_cache :: proc() {
	virtual.arena_destroy(&projects_cache.arena)
}
