package main

import "core:log"

import http "lib:odin-http"
import temple "lib:temple"

projects_page :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	Page_Data :: struct {
		using base:     Base_Page_Data,
		Username:       string,
		HayekFR:        string,
		HayekFRRepo:    string,
		Dotfiles:       string,
		GitLabProjects: []Standardized_Project,
		GitHubProjects: []Standardized_Project,
		Notice:         string,
	}

	notice := ""
	projects_cache, projects_err := fetch_projects(&app.projects, &app.config, &app.me, use_cache = true)
	if projects_err.type != .None {
		log.warn(projects_err.msg)
		notice = "Live project data is temporarily unavailable. Cached projects are shown when available."
	}
	data := Page_Data {
		base = create_base_page_data(
			app,
			Maybe_SEO_Data {
				title = "projects / sacha.house",
				description = "My personal projects.",
			},
			req.url.path,
			get_auth_level(&app.sessions, &app.config, req, res) == .Authorized,
		),
		Username = app.me.username,
		HayekFR = app.me.hayekfr,
		HayekFRRepo = app.me.hayekfrRepo,
		Dotfiles = app.me.dotfiles,
		GitLabProjects = projects_cache.gitlab,
		GitHubProjects = projects_cache.github,
		Notice = notice,
	}
	page_template := temple.compiled("templates/projects.temple.twig", Page_Data)
	render_page(req, res, page_template, data)
}

admin_refresh_projects :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	app := app_from_handler(handler)
	log.infof("Serving %v", req.url.path)
	if !ensure_admin_post(app, req, res) {
		return
	}
	Context_Data :: struct {
		app: ^App_State,
		req: ^http.Request,
		res: ^http.Response,
	}
	ctx := new_clone(Context_Data {app = app, req = req, res = res})
	http.body(req, MAX_ADMIN_ACTION_BODY_BYTES, ctx, proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
		ctx := cast(^Context_Data)user_data
		defer free(ctx)
		if err != nil {
			http.respond(ctx.res, http.body_error_status(err))
			return
		}
		defer paste_wipe_string(string(body))
		form_data, ok := http.body_url_encoded(body)
		if !ok {
			http.respond_with_status(ctx.res, http.Status.Bad_Request)
			return
		}
		if !validate_admin_post_csrf(
			ctx.app,
			ctx.req,
			ctx.res,
			form_data["csrf_token"] or_else "",
		) {
			return
		}
		_, refresh_err := fetch_projects(&ctx.app.projects, &ctx.app.config, &ctx.app.me, use_cache = false)
		if refresh_err.type != .None {
			log.error(refresh_err.msg)
		}
		http.headers_set(&ctx.res.headers, "Location", "/projects")
		http.respond(ctx.res, http.Status.See_Other)
	})
}
