export interface Node {
	name: string;
	url: string;
	description: string;
}

export interface Projects {
	nodes: Node[];
}

export interface User {
	username: string;
	projects: Projects;
}

export interface Github {
	user: User;
}

export interface Node3 {
	name: string;
	url: string;
	avatarUrl: string;
	description: string;
}

export interface Projects2 {
	nodes: Node3[];
}

export interface Node2 {
	name: string;
	projects: Projects2;
}

export interface Groups {
	nodes: Node2[];
}

export interface Project {
	name: string;
	url: string;
	avatarUrl: string;
	description: string;
}

export interface Node4 {
	project: Project;
}

export interface ProjectMemberships {
	nodes: Node4[];
}

export interface User2 {
	username: string;
	groups: Groups;
	projectMemberships: ProjectMemberships;
}

export interface Gitlab {
	user: User2;
}

export interface Data {
	github: Github;
	gitlab: Gitlab;
}
