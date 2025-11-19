package main

Post :: struct {
	slug:      string,
	title:     string,
	updatedAt: string,
	author: Post_Author,
}

Posts_Response :: struct {
	data: struct {
		posts: []Post,
	},
}

Post_Author :: struct {
	name: string,
}

Post_Detail :: struct {
	slug:      string,
	title:     string,
	updatedAt: string,
	createdAt: string,
	author:    Post_Author,
	content:   struct {
		html: string,
		text: string,
	},
}

Post_Response :: struct {
	data: struct {
		post: Post_Detail,
	},
}

Template_Post_Detail :: struct {
	slug:          string,
	title:         string,
	updatedAt:     string,
	createdAt:     string,
	updatedOn:     string,
	updatedAtTime: string,
	createdOn:     string,
	createdAtTime: string,
	author:        string,
	content:       struct {
		html: string,
		text: string,
	},
}

Template_Experience :: struct {
	title:              string,
	company:            string,
	location:           string,
	starts_at:          string,
	ends_at:            string,
	description:        string,
	company_linkedin_profile_url: string,
}

Template_Education :: struct {
	school:            string,
	degree_name:       string,
	field_of_study:    string,
	starts_at:         string,
	ends_at:           string,
	description:       string,
	school_linkedin_profile_url: string,
	title:             string,
}

GraphQL_Request :: struct {
	query:     string,
	variables: map[string]string,
}