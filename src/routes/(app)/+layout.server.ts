import { env as envPriv } from '$env/dynamic/private';
import { env as envPub } from '$env/dynamic/public';
import { updateCounter } from '$lib/countapi';
import type { LatestCommit } from '$lib/interfaces/LatestCommit';
import { getAuthorizedNavItems } from '$lib/nav';
import { GET_LATEST_COMMIT } from '$lib/queries';
import { GraphQLClient } from 'graphql-request';

export const load = async ({ fetch, getClientAddress, cookies }) => {
	const clientAddress = getClientAddress();
	const navItems = getAuthorizedNavItems(clientAddress);

	// on ne compte les visites qu'une fois par visiteur
	// une fois qu'on a incrémenté le compteur,
	// on valorise le cookie "visite" à "true"
	if (!(JSON.parse(cookies.get('visite') || 'false') as boolean)) {
		updateCounter();
		cookies.set('visite', JSON.stringify(true));
		console.log('Cookie de visite défini');
	}

	const commitHash = async () => {
		try {
			const clientGL = new GraphQLClient(`${envPub.PUBLIC_GITLAB_API_ENDPOINT}/graphql`, {
				fetch,
				headers: {
					Authorization: `Bearer ${envPriv.GITLAB_BEARER_TOKEN}`
				}
			});
			const GL: LatestCommit = await clientGL.request(GET_LATEST_COMMIT, {
				repoID: envPub.PUBLIC_GIT_REPO_ID
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
