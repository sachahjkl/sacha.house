package main

import "core:fmt"
import "core:log"
import "core:net"

import http "lib:odin-http"
import temple "lib:temple"

index_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	Page_Data :: struct {
		using base: Base_Page_Data,
		Mail:  string,
		Cv:    string,
	}

	data := Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data {
				title = "home / sacha.house",
				description = fmt.tprintf("%s's personal website.", app.me.fullName),
			},
			req.url.path,
			get_auth_level(&app.sessions, &app.config, req, res) == .Authorized,
		),
		Mail = app.me.mail,
		Cv = app.me.curriculumVitae,
	}
	page_template := temple.compiled("templates/index.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}

debug_logo_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	data := create_base_page_data(
		app,
		Maybe_SEO_Data {
			title = "logo debug / sacha.house",
			description = "Debug page for the live ASCII logo renderer.",
		},
		req.url.path,
		get_auth_level(&app.sessions, &app.config, req, res) == .Authorized,
	)
	page_template := temple.compiled("templates/debug_logo.temple.twig", Base_Page_Data)
	render_page(req, res, page_template, data)
}

about_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
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

	profile, _ := get_embedded_profile(&app.static)
	template_experiences := make([]Template_Experience, len(profile.experiences), context.temp_allocator)
	for exp, i in profile.experiences {
		template_experiences[i] = Template_Experience {
			title = exp.title,
			company = exp.company,
			location = exp.location,
			starts_at = format_linkedin_date(exp.starts_at),
			ends_at = format_linkedin_date(exp.ends_at),
			description = exp.description,
			company_linkedin_profile_url = exp.company_linkedin_profile_url,
		}
	}

	template_education := make([]Template_Education, len(profile.education), context.temp_allocator)
	for edu, i in profile.education {
		template_education[i] = Template_Education {
			school = edu.school,
			degree_name = edu.degree_name,
			field_of_study = edu.field_of_study,
			starts_at = format_linkedin_date(edu.starts_at),
			ends_at = format_linkedin_date(edu.ends_at),
			description = edu.description,
			school_linkedin_profile_url = edu.school_linkedin_profile_url,
			title = fmt.tprintf("%s in %s", edu.degree_name, edu.field_of_study),
		}
	}

	data := Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data {
				title = "about / sacha.house",
				description = fmt.tprintf(
					"Presentation of %s %s. You can find my contact details, my CV and a brief presentation of who I am.",
					app.me.prenom,
					app.me.nom,
				),
			},
			req.url.path,
			get_auth_level(&app.sessions, &app.config, req, res) == .Authorized,
		),
		Prenom = capitalize(app.me.prenom),
		Age = app.me.age,
		PlaceOfLiving = app.me.placeOfLiving,
		CurriculumVitae = app.me.curriculumVitae,
		Mail = app.me.mail,
		EthAddress = app.me.ethAddress,
		MoneroAddress = app.me.moneroAdress,
		GpgPrint = app.me.gpgPrint,
		Linkedin = app.me.linkedin,
		Github = app.me.github,
		Gitlab = app.me.gitlab,
		LinkedInExperiences = template_experiences,
		LinkedInEducation = template_education,
	}
	page_template := temple.compiled("templates/about.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}

ping :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if app.options.hot_reload {
		http.headers_set(&res.headers, "X-Dev-Server-Boot", app.server_boot_id)
		http.headers_set(&res.headers, "Cache-Control", "no-store")
	}
	http.respond_plain(res, "pong")
}

teapot_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
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

	brew_message := Brew_Message{}
	status := http.Status.OK
	is_a_teapot := false
	if drink, ok := http.query_get_percent_decoded(req.url, "drink"); ok {
		switch drink {
		case "tea":
			brew_message = Brew_Message{text = "Here is your tea!", emoji = "🍵"}
		case "coffee":
			status = .Im_A_Teapot
			is_a_teapot = true
			brew_message = Brew_Message{text = "Did you really think a teapot could brew you coffee ??\nare you some kind of lunatic or something ?"}
		case:
			brew_message = Brew_Message {
				text = fmt.tprintf("What kind of a drink is \"%s\" ???", drink),
				emoji = "🤮",
			}
		}
	}

	data := Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data{title = "teapot / sacha.house", description = "I'm a teapot."},
			req.url.path,
			get_auth_level(&app.sessions, &app.config, req, res) == .Authorized,
		),
		Spewage = generate_random_string(5, "abcdefghijklmnopqrstuvwxyz1234567890"),
		BrewMessage = brew_message,
		IsATeapot = is_a_teapot,
	}
	page_template := temple.compiled("templates/teapot.temple.twig", Page_Data)
	render_page(req, res, page_template, data, status)
}

ip_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	ip_api(handler, req, res)
}

ip_api :: proc(_: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	log.infof("Serving %v", req.url.path)
	http.respond_plain(res, net.address_to_string(req.client.address))
}
