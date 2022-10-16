export type LinkedinProfile = {
	public_identifier: string;
	profile_pic_url: string;
	background_cover_image_url: string;
	first_name: string;
	last_name: string;
	full_name: string;
	occupation: string;
	headline: string;
	summary: string;
	country: string;
	country_full_name: string;
	city: string;
	state: string;
	experiences: Experience[];
	education: Education[];
	languages: Array<string>;
	accomplishment_organisations: Array<string>;
	accomplishment_publications: Array<string>;
	accomplishment_honors_awards: Array<string>;
	accomplishment_patents: Array<string>;
	accomplishment_courses: Array<string>;
	accomplishment_projects: Array<string>;
	accomplishment_test_scores: Array<string>;
	volunteer_work: Array<string>;
	certifications: Array<string>;
	connections: number;
	people_also_viewed: Array<string>;
	recommendations: Array<string>;
	activities: Array<{
		title: string;
		link: string;
		activity_status: string;
	}>;
	similarly_named_profiles: Array<{
		name: string;
		link: string;
		summary: string;
		location: string;
	}>;
	articles: Array<string>;
	groups: Array<string>;
};

export interface Education {
	starts_at: Day;
	ends_at: Day;
	field_of_study: string;
	degree_name: string;
	school: string;
	school_linkedin_profile_url: string;
	description?: string;
	logo_url: string;
}

export interface Experience {
	starts_at: Day;
	ends_at: Day;
	company: string;
	company_linkedin_profile_url: string;
	title: string;
	description: string;
	location: string;
	logo_url: string;
}

interface Day {
	day: number;
	month: number;
	year: number;
}
