import { GET_PROJECTS_GITHUB, GET_PROJECTS_GITLAB } from '$lib/queries';
import { PUBLIC_GITHUB_API_ENDPOINT, PUBLIC_GITLAB_API_ENDPOINT } from '$env/static/public';
import type { Project, ProjetsResponse } from '$lib/interfaces/Project';
import { SECRET_GITHUB_BEARER_TOKEN, SECRET_GITLAB_BEARER_TOKEN } from '$env/static/private';
import { error, json } from '@sveltejs/kit';

import { GraphQLClient } from 'graphql-request';
import { MOI } from '$lib/me';
import type { RequestHandler } from './$types';

export type GHType = { user: { projects: { nodes: Project[] } } };
export type GLType = { projects: { nodes: Project[] } };

export const GET = (async () => {
	try {
		const clientGH = new GraphQLClient(`${PUBLIC_GITHUB_API_ENDPOINT}/graphql`, {
			headers: {
				Authorization: `Bearer ${SECRET_GITHUB_BEARER_TOKEN}`
			}
		});
		const clientGL = new GraphQLClient(`${PUBLIC_GITLAB_API_ENDPOINT}/graphql`, {
			headers: {
				Authorization: `Bearer ${SECRET_GITLAB_BEARER_TOKEN}`
			}
		});
		const GH: GHType = await clientGH.request(GET_PROJECTS_GITHUB, { username: MOI.username });
		const GL: GLType = await clientGL.request(GET_PROJECTS_GITLAB, { username: MOI.username });
		console.log('Données de GitHub et GitLab reçues', { GH, GL });
		const nodesGH = GH.user.projects.nodes;
		const nodesGL = GL.projects.nodes;

		const removePrivate = (node: Project) => node.visibility.toLowerCase() !== 'private';

		const response: ProjetsResponse = {
			github: nodesGH.filter(removePrivate),
			gitlab: nodesGL.filter(removePrivate)
		};
		return json(response, {
			headers: {
				'Cache-Control': 'max-age=3600'
			}
		});
	} catch (err) {
		console.error('Problème à la récupération des projets', err);
		throw error(500, 'Impossible de récupérer les données des projets.');
	}
}) satisfies RequestHandler;
