import { MOI } from '$lib/me';

import { env as envPriv } from '$env/dynamic/private';
import { env as envPub } from '$env/dynamic/public';
import type { LinkedinProfile } from '$lib/interfaces/LinkedinProfile';
import { updateCounter } from '$lib/server/countapi';
import { fail } from '@sveltejs/kit';

export const load = async ({ getClientAddress, fetch }) => {
	const creditBalance = await fetch('/api/creditBalance')
		.then((res) => res.text())
		.then((str) => Number(str))
		.catch(() => 0);

	const profile = await fetch('/api/linkedinProfile').then<LinkedinProfile>((res) => res.json());

	return {
		creditBalance,
		profile,
		ip: getClientAddress(),
		seo: {
			title: `admin / ${MOI.siteTitle}`,
			description: "Panneau d'administration du site."
		}
	};
};

export const actions = {
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
				`${envPub.PUBLIC_GITHUB_API_ENDPOINT}/gists/${envPub.PUBLIC_LINKEDIN_GIST_ID}`,
				{
					method: 'PATCH',
					body: JSON.stringify(gist),
					headers: {
						Accept: 'application/vnd.github+json',
						Authorization: `Bearer ${envPriv.GITHUB_BEARER_TOKEN}`
					}
				}
			);

			if (!gistRes.ok) {
				console.error('Mise à jour du gist échouee. erreur : ', gistRes.status);
				return fail(500, {
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
				return fail(500, {
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
			return fail(500, {
				error: true,
				message: err
			});
		}
	}
};

const fetchProxyCurl = async () => {
	const proxyCurlURL = new URL(`${envPub.PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/v2/linkedin`);
	proxyCurlURL.searchParams.append('url', MOI.linkedin.toString());
	proxyCurlURL.searchParams.append('fallback_to_cache', 'on-error');

	const res = await fetch(proxyCurlURL.toString(), {
		headers: {
			Authorization: `Bearer ${envPriv.PROXYCURL_BEARER_TOKEN}`
		}
	});
	if (!res.ok) throw new Error(`Récupération du profil échouée.`);
	return (await res.json()) as LinkedinProfile;
};
