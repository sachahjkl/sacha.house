import { PUBLIC_GITLAB_API_ENDPOINT, PUBLIC_GIT_REPO_ID } from '$env/static/public';

import { GET_LATEST_COMMIT } from '$lib/queries';
import { GraphQLClient } from 'graphql-request';
import type { LatestCommit } from '$lib/interfaces/LatestCommit';
import type { LayoutServerLoad } from './$types';
import { SECRET_GITLAB_BEARER_TOKEN } from '$env/static/private';
import { getAuthorizedNavItems } from '$lib/nav';
import { updateCounter } from '$lib/countapi';

export const load: LayoutServerLoad = async ({ fetch, getClientAddress, cookies }) => {
	const clientAddress = getClientAddress();
	const navItems = getAuthorizedNavItems(clientAddress);

	// on ne compte les visites qu'une fois par visiteur
	if (!(JSON.parse(cookies.get('visite') || 'false') as boolean)) {
		updateCounter(fetch);
		cookies.set('visite', JSON.stringify(true));
		console.log('Cookie de visite défini');
	}

	const commitHash = async () => {
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
			return `${GL.project.repository.paginatedTree.nodes.at(0)?.lastCommit.sha}`;
		} catch (error) {
			console.error('Erreur à la récupération du hash de version du dépôt.');
		}
		return 'inconnu';
	};

	return {
		navItems,
		commitHash: commitHash()
	};
};
