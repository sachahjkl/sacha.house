package main

import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:net"
import "core:os"
import "core:sort"
import "core:strings"
import "core:time"
import http "lib:odin-http"
import client "lib:odin-http/client"
import temple "lib:temple"


// NOTE(sachahjkl):
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

	// NOTE(sachahjkl):
	// - Routes are tried in order, so the more specific routes should be placed first.
	// - route patterns follow the Lua pattern syntax, see https://www.lua.org/pil/20.2.html and special characters are escaped with a '%' (eg. %-).

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
	http.route_get(&router, "/admin/login", http.handler(admin_login_page))
	http.route_post(&router, "/admin/login", http.handler(admin_login_submit))
	http.route_get(&router, "/admin/logout", http.handler(admin_logout))
	http.route_get(&router, "/admin", http.handler(admin_page))
	http.route_get(
		&router,
		"/admin/webauthn/register%-challenge",
		http.handler(admin_webauthn_register_challenge),
	)
	http.route_post(&router, "/admin/webauthn/register", http.handler(admin_webauthn_register))
	http.route_get(
		&router,
		"/admin/webauthn/login%-challenge",
		http.handler(admin_webauthn_login_challenge),
	)
	http.route_post(&router, "/admin/webauthn/login", http.handler(admin_webauthn_login))
	http.route_post(&router, "/admin/refresh%-projects", http.handler(admin_refresh_projects))

	// fallback to static serve but from the root
	http.route_get(&router, "/(.*)", http.handler(serve_static_file))

	log.info("Routes initialized.")

	routed := http.router_handler(&router)

	if init_cache() != .None {
		log.error("Failed to initialize cache")
		return
	}

	log.info("Cache initialized.")

	defer cleanup_cache()

	if err := init_sessions(); err != .None {
		log.fatalf("Failed to initialize sessions: %v", err)
	}
	defer cleanup_sessions()

	if err := init_webauthn(); err != .None {
		log.fatalf("Failed to initialize WebAuthn: %v", err)
	}
	defer cleanup_webauthn()

	listen_endpoint := net.Endpoint {
		address = net.IP4_Any,
		port    = get_port(),
	}

	log.infof("Listening on http://localhost:%d", listen_endpoint.port)

	err := http.listen_and_serve(&s, routed, listen_endpoint)

	fmt.assertf(err == nil, "server stopped with error: %v", err)
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
			get_auth_level(req, res) == .Authorized,
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
			get_auth_level(req, res) == .Authorized,
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

	page_template := temple.compiled("templates/about.temple.twig", Page_Data)
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
			get_auth_level(req, res) == .Authorized,
		),
		Posts = template_posts,
	}

	page_template := temple.compiled("templates/posts.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}

blog_post_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	Page_Data :: struct {
		using base: Base_Page_Data,
		Post:       Template_Post_Detail,
	}


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
				description = string(post.content.text[:min(len(post.content.text), 160)]),
			},
			req.url.path,
			get_auth_level(req, res) == .Authorized,
		),
		Post = template_post,
	}
	page_template := temple.compiled("templates/post.temple.twig", Page_Data)
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
			get_auth_level(req, res) == .Authorized,
		),
		Spewage     = next_spewage,
		BrewMessage = brew_message,
		IsATeapot   = is_a_teapot,
	}

	page_template := temple.compiled("templates/teapot.temple.twig", Page_Data)
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
		GitLabProjects: []Standardized_Project,
		GitHubProjects: []Standardized_Project,
	}

	projects_cache := fetch_projects(use_cache = true)

	if projects_cache == nil {
		log.error("Failed to fetch projects")
		http.respond_with_status(res, http.Status.Internal_Server_Error)
		return
	}

	data := Page_Data {
		base           = create_base_page_data(
			Maybe_SEO_Data {
				title = "projects / sacha.house",
				description = "My personal projects.",
			},
			req.url.path,
			get_auth_level(req, res) == .Authorized,
		),
		Username       = ME.username,
		HayekFR        = ME.hayekfr,
		HayekFRRepo    = ME.hayekfrRepo,
		Dotfiles       = ME.dotfiles,
		GitLabProjects = projects_cache.gitlab,
		GitHubProjects = projects_cache.github,
	}

	page_template := temple.compiled("templates/projects.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}

admin_refresh_projects :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	if get_auth_level(req, res) != .Authorized {
		http.headers_set(&res.headers, "Location", "/admin/login")
		http.respond(res, http.Status.Temporary_Redirect)
		return
	}

	fetch_projects(use_cache = false)

	http.headers_set(&res.headers, "Location", "/projects")
	http.respond(res, http.Status.See_Other)
}

Webauthn_Credential_Response :: struct {
	id:       string,
	rawId:    string,
	response: struct {
		clientDataJSON:    string,
		attestationObject: string,
	},
	type:     string,
}

Webauthn_Assertion_Response :: struct {
	id:       string,
	rawId:    string,
	response: struct {
		clientDataJSON:    string,
		authenticatorData: string,
		signature:         string,
		userHandle:        string,
	},
	type:     string,
}

admin_login_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)

	// Redirect to admin if already authenticated
	if get_auth_level(req, res) == .Authorized {
		http.headers_set(&res.headers, "Location", "/admin")
		http.respond(res, http.Status.Temporary_Redirect)
		return
	}

	Page_Data :: struct {
		using base: Base_Page_Data,
		Error:      string,
	}
	page_template := temple.compiled("templates/admin_login.temple.twig", Page_Data)

	data := Page_Data {
		base  = create_base_page_data(
			Maybe_SEO_Data{title = "admin login / sacha.house", description = "Admin login."},
			req.url.path,
			false,
		),
		Error = "",
	}

	render_page(req, res, page_template, data)
}

admin_login_submit :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)

	Context_Data :: struct {
		res:           ^http.Response,
		req:           ^http.Request,
		form_template: temple.Compiled(Login_Form_Data),
	}


	Login_Form_Data :: struct {
		Error: string,
	}

	// Check credentials
	form_template := temple.compiled("templates/_login_form.temple.twig", Login_Form_Data)


	ctx := Context_Data {
		res           = res,
		req           = req,
		form_template = form_template,
	}

	http.body(
		req,
		-1,
		&ctx,
		proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
			ctx := cast(^Context_Data)user_data
			res := ctx.res
			req := ctx.req
			form_template := ctx.form_template

			if err != nil {
				http.respond_with_status(res, http.Status.Bad_Request)
				return
			}

			// Parse form data from body
			form_data, ok := http.body_url_encoded(body)
			if !ok {
				http.respond_with_status(res, http.Status.Bad_Request)
				return
			}

			username := form_data["username"] or_else ""
			password := form_data["password"] or_else ""


			if username == get_admin_username() && password == get_admin_password() {
				// Create session and redirect
				session_id := create_session()
				set_session_cookie(res, session_id)
				http.headers_set(&res.headers, "HX-Redirect", "/admin")
				http.respond_with_status(res, http.Status.OK)
			} else {
				// Invalid credentials, render form with error

				data := Login_Form_Data {
					Error = "Invalid username or password",
				}

				render_page(req, res, form_template, data)
			}
		},
	)
}

admin_logout :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)

	// Clear the session cookie
	clear_session_cookie(res)

	// Redirect to login page
	http.headers_set(&res.headers, "HX-Redirect", "/admin/login")
	http.headers_set(&res.headers, "Location", "/admin/login")
	http.respond(res, http.Status.Temporary_Redirect)
}

admin_page :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)

	// Require authentication
	if get_auth_level(req, res) != .Authorized {
		http.headers_set(&res.headers, "Location", "/admin/login")
		http.respond(res, http.Status.Temporary_Redirect)
		return
	}

	Page_Data :: struct {
		using base:    Base_Page_Data,
		IpAddress:     string,
		CreditBalance: int,
		ProfileData:   string,
	}

	profile_json := ""
	if profile_json_str := get_gist_profile_string(); profile_json_str != nil {
		profile_json = profile_json_str.(string)
	}

	data := Page_Data {
		base          = create_base_page_data(
			Maybe_SEO_Data{title = "admin / sacha.house", description = "Admin panel."},
			req.url.path,
			true,
		),
		IpAddress     = net.address_to_string(req.client.address),
		CreditBalance = 0,
		ProfileData   = profile_json,
	}

	page_template := temple.compiled("templates/admin.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}


admin_webauthn_register_challenge :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)

	// Require authentication for WebAuthn registration
	if get_auth_level(req, res) != .Authorized {
		http.respond_with_status(res, http.Status.Unauthorized)
		return
	}

	challenge_id := generate_id()
	log.infof("Challenge ID: %s", challenge_id)

	challenge := generate_challenge()
	log.infof("Generated challenge: %d bytes", len(challenge))

	store_challenge(challenge_id, challenge)
	log.infof("Stored challenge for session")

	rp_id := get_rp_id(req)
	log.infof("RP ID: %s", rp_id)

	Challenge_Response :: struct {
		challenge: string,
		rp_id:     string,
		user_id:   string,
	}

	challenge_b64 := base64.encode(challenge, allocator = context.temp_allocator)
	log.infof("Challenge base64: %s", challenge_b64)

	response := Challenge_Response {
		challenge = challenge_b64,
		rp_id     = rp_id,
		user_id   = "admin",
	}

	json_data, err := json.marshal(response, allocator = context.temp_allocator)
	if err != nil {
		log.errorf("Failed to marshal challenge response: %v", err)
		http.respond_plain(res, "JSON marshal error", http.Status.Internal_Server_Error)
		return
	}

	set_challenge_cookie(res, challenge_id)

	http.headers_set(&res.headers, "Content-Type", "application/json")
	http.respond_plain(res, string(json_data), http.Status.OK)
}

admin_webauthn_register :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	// Require authentication for WebAuthn registration
	if get_auth_level(req, res) != .Authorized {
		http.respond_with_status(res, http.Status.Unauthorized)
		return
	}

	// Get or create session (reuse existing if available)
	challenge_id, ok := http.request_cookie_get(req, CHALLENGE_KEY)

	if !ok {
		http.respond_plain(res, "No challenge ID found", http.Status.Bad_Request)
		return
	}

	Context_Data :: struct {
		res:          ^http.Response,
		challenge_id: string,
	}

	ctx := Context_Data {
		res          = res,
		challenge_id = challenge_id,
	}

	http.body(
		req,
		-1,
		&ctx,
		proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
			ctx := cast(^Context_Data)user_data
			res := ctx.res
			challenge_id := ctx.challenge_id

			if err != nil {
				http.respond(res, http.body_error_status(err))
				return
			}

			cred_data: Webauthn_Credential_Response
			if uerr := json.unmarshal(
				transmute([]byte)body,
				&cred_data,
				allocator = context.temp_allocator,
			); uerr != nil {
				http.respond_plain(res, "Invalid JSON", http.Status.Bad_Request)
				return
			}


			client_data, cok := parse_client_data_json(cred_data.response.clientDataJSON)
			if !cok {
				http.respond_plain(res, "Invalid clientDataJSON", http.Status.Bad_Request)
				return
			}


			challenge_val, has_challenge := client_data["challenge"]
			if !has_challenge {
				http.respond_plain(res, "Missing challenge", http.Status.Bad_Request)
				return
			}

			challenge_str, is_string := challenge_val.(string)
			if !is_string {
				http.respond_plain(res, "Invalid challenge type", http.Status.Bad_Request)
				return
			}

			// Convert URL-safe base64 to standard base64
			standard_challenge, _ := strings.replace_all(
				challenge_str,
				"-",
				"+",
				context.temp_allocator,
			)
			standard_challenge, _ = strings.replace_all(
				standard_challenge,
				"_",
				"/",
				context.temp_allocator,
			)

			challenge_bytes := base64.decode(
				standard_challenge,
				allocator = context.temp_allocator,
			)
			if challenge_bytes == nil {
				http.respond_plain(res, "Invalid challenge encoding", http.Status.Bad_Request)
				return
			}


			if !verify_and_consume_challenge(challenge_id, challenge_bytes) {
				log.errorf("Challenge verification failed for challenge: %s", challenge_id)
				http.respond_plain(res, "Challenge verification failed", http.Status.Bad_Request)
				return
			}


			public_key, parse_ok := verify_attestation_object(cred_data.response.attestationObject)
			if !parse_ok {
				http.respond_plain(res, "Failed to parse attestation", http.Status.Bad_Request)
				return
			}

			// Store using the credential ID sent by the client (URL-safe base64)
			// This must match what the client sends during login
			store_credential(cred_data.id, public_key)

			// Cleanup the challenge cookie
			clear_challenge_cookie(res)

			log.infof("Registered WebAuthn credential: %s", cred_data.id)
			http.respond_plain(res, "Registration successful", http.Status.OK)
		},
	)
}

admin_webauthn_login_challenge :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)

	if !has_credentials() {
		http.respond_plain(res, "No passkeys registered yet", http.Status.Bad_Request)
		return
	}

	challenge_id := generate_id()
	log.infof("Challenge ID: %s", challenge_id)

	challenge := generate_challenge()
	store_challenge(challenge_id, challenge)


	rp_id := get_rp_id(req)

	Challenge_Response :: struct {
		challenge: string,
		rp_id:     string,
	}

	response := Challenge_Response {
		challenge = base64.encode(challenge, allocator = context.temp_allocator),
		rp_id     = rp_id,
	}

	json_data, err := json.marshal(response, allocator = context.temp_allocator)
	if err != nil {
		log.errorf("Failed to marshal challenge response: %v", err)
		http.respond_with_status(res, http.Status.Internal_Server_Error)
		return
	}

	set_challenge_cookie(res, challenge_id)

	http.headers_set(&res.headers, "Content-Type", "application/json")
	http.respond_plain(res, string(json_data), http.Status.OK)
}

admin_webauthn_login :: proc(req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)

	challenge_id, ok := http.request_cookie_get(req, CHALLENGE_KEY)
	if !ok {
		http.respond_plain(res, "No challenge ID found", http.Status.Bad_Request)
		return
	}

	Context_Data :: struct {
		res:          ^http.Response,
		challenge_id: string,
	}

	ctx := Context_Data {
		res          = res,
		challenge_id = challenge_id,
	}

	http.body(
		req,
		-1,
		&ctx,
		proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
			ctx := cast(^Context_Data)user_data
			res := ctx.res
			challenge_id := ctx.challenge_id

			if err != nil {
				http.respond(res, http.body_error_status(err))
				return
			}

			assertion_data: Webauthn_Assertion_Response
			if uerr := json.unmarshal(
				transmute([]byte)body,
				&assertion_data,
				allocator = context.temp_allocator,
			); uerr != nil {
				http.respond_plain(res, "Invalid JSON", http.Status.Bad_Request)
				return
			}


			client_data, cok := parse_client_data_json(assertion_data.response.clientDataJSON)
			if !cok {
				http.respond_plain(res, "Invalid clientDataJSON", http.Status.Bad_Request)
				return
			}

			challenge_val, has_challenge := client_data["challenge"]
			if !has_challenge {
				http.respond_plain(res, "Missing challenge", http.Status.Bad_Request)
				return
			}

			challenge_str, is_string := challenge_val.(string)
			if !is_string {
				http.respond_plain(res, "Invalid challenge type", http.Status.Bad_Request)
				return
			}

			// Convert URL-safe base64 to standard base64
			standard_challenge, _ := strings.replace_all(
				challenge_str,
				"-",
				"+",
				context.temp_allocator,
			)
			standard_challenge, _ = strings.replace_all(
				standard_challenge,
				"_",
				"/",
				context.temp_allocator,
			)

			challenge_bytes := base64.decode(
				standard_challenge,
				allocator = context.temp_allocator,
			)
			if challenge_bytes == nil {
				http.respond_plain(res, "Invalid challenge encoding", http.Status.Bad_Request)
				return
			}

			if !verify_and_consume_challenge(challenge_id, challenge_bytes) {
				http.respond_plain(res, "Challenge verification failed", http.Status.Bad_Request)
				return
			}

			credential, cred_ok := get_credential(assertion_data.id)
			if !cred_ok {
				http.respond_plain(res, "Unknown credential", http.Status.Unauthorized)
				return
			}

			if !verify_assertion_signature(
				credential,
				assertion_data.response.authenticatorData,
				assertion_data.response.clientDataJSON,
				assertion_data.response.signature,
			) {
				http.respond_plain(res, "Signature verification failed", http.Status.Unauthorized)
				return
			}

			// Grant a session
			new_session_id := create_session()
			set_session_cookie(res, new_session_id)

			// Cleanup the challenge cookie
			clear_challenge_cookie(res)

			log.info("WebAuthn login successful")
			http.respond_plain(res, "Login successful", http.Status.OK)
		},
	)
}

get_rp_id :: proc(req: ^http.Request) -> string {
	host :=
		http.headers_get(req.headers, "Host") or_else fmt.tprintf("%s:%d", "localhost", get_port())
	if strings.contains(host, ":") {
		host = host[:strings.index(host, ":")]
	}
	return host
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

fetch_posts :: proc() -> (posts: []Post, err: Error) {
	req_body: GraphQL_Request
	req_body.query = `
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
	req_body.query = `
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
	// Fuck it, let's load the projects cache on start
	first_load_projects_cache() or_return
	return .None
}

cleanup_cache :: proc() {
	cleanup_projects_cache()
}
