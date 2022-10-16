import { PUBLIC_GITLAB_API_ENDPOINT, PUBLIC_GIT_REPO_ID } from '$env/static/public';

import { GET_LATEST_COMMIT } from '$lib/queries';
import { GraphQLClient } from 'graphql-request';
import type { LayoutServerLoad } from './$types';
import type { Result } from 'countapi-js';
import { SECRET_GITLAB_BEARER_TOKEN } from '$env/static/private';
import { countAPIConfig } from '$lib/constants';
import { getAuthorizedNavItems } from '$lib/nav';

interface LatestCommit {
	project: {
		repository: {
			rootRef: string;
			paginatedTree: {
				nodes: Array<{
					lastCommit: {
						sha: string;
					};
				}>;
			};
		};
	};
}

export const load: LayoutServerLoad = async ({ fetch, getClientAddress }) => {
	const clientAddress = getClientAddress();
	let commitHash = 'inconnue';
	const { key, namespace } = countAPIConfig;
	let visites = -1;
	try {
		const participants: Promise<Result> = (
			await fetch(`https://api.countapi.xyz/hit/${namespace}/${key}`)
		).json();
		visites = (await participants).value;
	} catch {
		console.error("Erreur à l'incrémentation du compteur de visites.");
	}
	try {
		const clientGL = new GraphQLClient(`${PUBLIC_GITLAB_API_ENDPOINT}/graphql`, {
			fetch,
			headers: {
				Authorization: `Bearer ${SECRET_GITLAB_BEARER_TOKEN}`
			}
		});
		const GL: LatestCommit = await clientGL.request(GET_LATEST_COMMIT, {
			repoID: PUBLIC_GIT_REPO_ID
		});
		commitHash = GL.project.repository.paginatedTree.nodes.at(0)?.lastCommit.sha || commitHash;
	} catch (error) {
		console.error('Erreur à la récupération du hash de version du dépôt.');
	}
	return {
		navItems: getAuthorizedNavItems(clientAddress),
		visites,
		commitHash
	};
};
