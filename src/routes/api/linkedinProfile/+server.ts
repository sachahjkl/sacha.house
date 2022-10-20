import { PUBLIC_GITHUB_API_ENDPOINT, PUBLIC_LINKEDIN_GIST_ID } from '$env/static/public';
import { error, json } from '@sveltejs/kit';

import type { LinkedinProfile } from '$lib/interfaces/LinkedinProfile';
import type { RequestHandler } from './$types';
import { SECRET_GITHUB_BEARER_TOKEN } from '$env/static/private';

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
		return json(JSON.parse(gist.files['linkedin_profile.json'].content), {
			headers: {
				'Cache-Control': 'max-age=3600'
			}
		});
	} catch (err) {
		console.error('Récupération du gist échouée.', err);
		throw error(500, 'Erreur inattendue, récupération du gist échouée.');
	}
};
