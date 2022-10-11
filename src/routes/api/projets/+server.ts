import type { RequestHandler } from './$types';

import { PUBLIC_GITHUB_API_ENDPOINT, PUBLIC_GITLAB_API_ENDPOINT } from '$env/static/public';
import { MOI } from '$lib/constants';
import { GET_PROJECTS_GITHUB, GET_PROJECTS_GITLAB } from '$lib/queries';
import { SECRET_GITHUB_BEARER_TOKEN, SECRET_GITLAB_BEARER_TOKEN } from '$env/static/private';
import { makeGqlBody } from '$lib/queries';
import { json, error } from '@sveltejs/kit';
import type { Project } from '$lib/interfaces/Project';

export interface ProjetsResponse {
	github: Project[];
	gitlab: Project[];
}

export const GET: RequestHandler = async ({ fetch }) => {
	try {
		const promiseGH = fetch(PUBLIC_GITHUB_API_ENDPOINT, {
			method: 'POST',
			body: makeGqlBody(GET_PROJECTS_GITHUB, { username: MOI.username }),
			headers: {
				Authorization: `Bearer ${SECRET_GITHUB_BEARER_TOKEN}`,
				'Content-Type': 'application/json'
			}
		});
		const promiseGL = fetch(PUBLIC_GITLAB_API_ENDPOINT, {
			method: 'POST',
			body: makeGqlBody(GET_PROJECTS_GITLAB, { username: MOI.username }),
			headers: {
				Authorization: `Bearer ${SECRET_GITLAB_BEARER_TOKEN}`,
				'Content-Type': 'application/json'
			}
		});
		const [resGH, resGL] = await Promise.all([promiseGH, promiseGL]);
		const GH = (await resGH.json()) as { data: { user: { projects: { nodes: Project[] } } } };
		const GL = (await resGL.json()) as { data: { projects: { nodes: Project[] } } };

		const removePrivate = (node: Project) => node.visibility.toLowerCase() !== 'private';

		const response: ProjetsResponse = {
			github: GH.data.user.projects.nodes.filter(removePrivate),
			gitlab: GL.data.projects.nodes.filter(removePrivate)
		};
		return json(response, {
			headers: {
				'Cache-Control': 'max-age=3600'
			}
		});
	} catch (err) {
		throw error(500, 'Impossible de récupérer les données des projets.');
	}
};
