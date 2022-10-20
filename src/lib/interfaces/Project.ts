export interface Project {
	name: string;
	url: string;
	avatarUrl?: string;
	description?: string;
	descriptionHtml?: string;
	visibility: Visibility;
	group?: Group;
}

export interface Group {
	name: string;
}

type Visibility = 'public' | 'private' | 'PUBLIC' | 'PRIVATE';

export interface ProjetsResponse {
	github: Project[];
	gitlab: Project[];
}
