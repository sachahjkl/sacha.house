import { SECRET_GITHUB_BEARER_TOKEN, SECRET_PROXYCURL_BEARER_TOKEN } from '$env/static/private';
import {
	PUBLIC_GITHUB_API_ENDPOINT,
	PUBLIC_LINKEDIN_GIST_ID,
	PUBLIC_PROXYCURL_API_ENDPOINT
} from '$env/static/public';
import { auth } from '$lib/auth';
import { MOI } from '$lib/constants';
import { HTTPMethod } from '$lib/interfaces/HTTP';
import type { LinkedinProfile } from '$lib/interfaces/LinkedinProfile';
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export interface UpdateProfileData {
	profile: LinkedinProfile;
	remainingCredit: number;
}

export const GET: RequestHandler = async ({ fetch }) => {
	try {
		const res = await fetch(`${PUBLIC_GITHUB_API_ENDPOINT}/gists/${PUBLIC_LINKEDIN_GIST_ID}`, {
			headers: {
				Accept: 'application/vnd.github+json',
				Authorization: `Bearer ${SECRET_GITHUB_BEARER_TOKEN}`
			}
		});
		if (!res.ok) throw error(500, 'Récupération du gist échouée.');
		const gist = (await res.json()) as { files: { 'linkedin_profile.json': { content: string } } };
		return json(JSON.parse(gist.files['linkedin_profile.json'].content));
	} catch (err) {
		console.error('Récupération du gist échouée.', err);
		throw error(500, 'Erreur inattendue, récupération du gist échouée.');
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
	if (!res.ok)
		throw error(
			500,
			`Récupération du profil échouée. "${await res.text()}";  ${proxyCurlURL.toString()}`
		);
	const profile = await res.json();
	return profile;
};

export const PATCH: RequestHandler = async ({ url, getClientAddress, fetch }) => {
	if (!auth(url.pathname, { clientAddress: getClientAddress(), method: HTTPMethod.PATCH })) {
		throw error(401, 'Pas autorisé à exécuter cette action.');
	}

	const profile: LinkedinProfile = await fetchProxyCurl();
	console.info('Profil LinkedIn récupéré :', JSON.stringify(profile));

	const gist = {
		files: {
			'linkedin_profile.json': {
				content: JSON.stringify(profile)
			}
		}
	};

	const gistRes = await fetch(`${PUBLIC_GITHUB_API_ENDPOINT}/gists/${PUBLIC_LINKEDIN_GIST_ID}`, {
		method: 'PATCH',
		body: JSON.stringify(gist),
		headers: {
			Accept: 'application/vnd.github+json',
			Authorization: `Bearer ${SECRET_GITHUB_BEARER_TOKEN}`
		}
	});
	if (!gistRes.ok) throw error(500, 'Mise à jour du gist échouée.');

	const newCreditBalance = await fetch('/api/admin/creditBalance').then((res) => res.text());
	console.log('Crédits restants : ', newCreditBalance);

	const data: UpdateProfileData = {
		profile,
		remainingCredit: Number(newCreditBalance)
	};
	return json(data);
};
