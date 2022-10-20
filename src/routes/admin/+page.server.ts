import type { Actions, PageServerLoad } from './$types';
import { MOI, SITE_TITLE } from '$lib/me';
import {
	PUBLIC_GITHUB_API_ENDPOINT,
	PUBLIC_LINKEDIN_GIST_ID,
	PUBLIC_PROXYCURL_API_ENDPOINT
} from '$env/static/public';
import { SECRET_GITHUB_BEARER_TOKEN, SECRET_PROXYCURL_BEARER_TOKEN } from '$env/static/private';

import type { LinkedinProfile } from '$lib/interfaces/LinkedinProfile';
import { invalid } from '@sveltejs/kit';
import { updateCounter } from '$lib/countapi';

export const load: PageServerLoad = async ({ getClientAddress, fetch }) => {
	const creditBalance: Promise<number> = fetch('/api/creditBalance')
		.then((res) => res.text())
		.then((str) => Number(str));

	const profile: Promise<LinkedinProfile> = fetch('/api/linkedinProfile').then((res) => res.json());
	const visites = fetch('/api/visites')
		.then((val) => val.text())
		.then((str) => Number(str));

	return {
		creditBalance,
		profile,
		visites,
		ip: getClientAddress(),
		seo: {
			title: `admin / ${SITE_TITLE}`,
			description: "Panneau d'administration du site."
		}
	};
};

export const actions: Actions = {
	updateLinkedinProfile: async (event) => {
		const localFetch = event.fetch;
		try {
			const newProfile = await fetchProxyCurl();
			console.info('Profil LinkedIn récupéré');

			const gist = {
				files: {
					'linkedin_profile.json': {
						content: JSON.stringify(newProfile)
					}
				}
			};

			const gistRes = await fetch(
				`${PUBLIC_GITHUB_API_ENDPOINT}/gists/${PUBLIC_LINKEDIN_GIST_ID}`,
				{
					method: 'PATCH',
					body: JSON.stringify(gist),
					headers: {
						Accept: 'application/vnd.github+json',
						Authorization: `Bearer ${SECRET_GITHUB_BEARER_TOKEN}`
					}
				}
			);

			if (!gistRes.ok) {
				console.error('Mise à jour du gist échouee. erreur : ', gistRes.status);
				return invalid(500, {
					error: true,
					message: 'Mise à jour du gist échouée.'
				});
			}

			const creditBalance = await localFetch('/api/creditBalance')
				.then((res) => res.text())
				.then((val) => Number(val));

			console.log('Crédits restants : ', creditBalance);

			return {
				success: true,
				creditBalance
			};
		} catch (error) {
			if (error instanceof Error) {
				console.error('Erreur à la maj du profile linkedin', { error });
				return invalid(500, {
					error: true,
					message: `Erreur innatendue - ${error.message}`
				});
			}
		}
	},

	incrementCounter: async () => {
		try {
			await updateCounter();
			return {
				success: true
			};
		} catch (err) {
			return invalid(500, {
				error: true,
				message: err
			});
		}
	}
};

const fetchProxyCurl = async () => {
	const proxyCurlURL = new URL(`${PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/v2/linkedin`);
	proxyCurlURL.searchParams.append('url', MOI.linkedin.toString());
	proxyCurlURL.searchParams.append('fallback_to_cache', 'on-error');

	const res = await fetch(proxyCurlURL.toString(), {
		headers: {
			Authorization: `Bearer ${SECRET_PROXYCURL_BEARER_TOKEN}`
		}
	});
	if (!res.ok) throw new Error(`Récupération du profil échouée.`);
	return (await res.json()) as LinkedinProfile;
};
