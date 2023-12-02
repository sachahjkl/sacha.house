import type { Project, ProjetsResponse } from '$lib/interfaces/Project';
import { GET_PROJECTS_GITHUB, GET_PROJECTS_GITLAB } from '$lib/queries';
import { error, json } from '@sveltejs/kit';

import { env as envPriv } from '$env/dynamic/private';
import { env as envPub } from '$env/dynamic/public';
import { MOI } from '$lib/me';
import { GraphQLClient } from 'graphql-request';

export type GHType = { user: { projects: { nodes: Project[] } } };
export type GLType = { projects: { nodes: Project[] } };

export const GET = async () => {
	try {
		const clientGH = new GraphQLClient(`${envPub.PUBLIC_GITHUB_API_ENDPOINT}/graphql`, {
			headers: {
				Authorization: `Bearer ${envPriv.GITHUB_BEARER_TOKEN}`
			}
		});
		const clientGL = new GraphQLClient(`${envPub.PUBLIC_GITLAB_API_ENDPOINT}/graphql`, {
			headers: {
				Authorization: `Bearer ${envPriv.GITLAB_BEARER_TOKEN}`
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
};
