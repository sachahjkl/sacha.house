import { error, json } from '@sveltejs/kit';

import { env as envPriv } from '$env/dynamic/private';
import { env as envPub } from '$env/dynamic/public';
import type { LinkedinProfile } from '$lib/interfaces/LinkedinProfile';

export interface UpdateProfileData {
	profile: LinkedinProfile;
	remainingCredit: number;
}

export const GET = async () => {
	try {
		const res = await fetch(
			`${envPub.PUBLIC_GITHUB_API_ENDPOINT}/gists/${envPub.PUBLIC_LINKEDIN_GIST_ID}`,
			{
				headers: {
					Accept: 'application/vnd.github+json',
					Authorization: `Bearer ${envPriv.GITHUB_BEARER_TOKEN}`
				}
			}
		);
		if (!res.ok) error(500, 'Récupération du gist échouée.');
		const gist = (await res.json()) as { files: { 'linkedin_profile.json': { content: string } } };
		return json(JSON.parse(gist.files['linkedin_profile.json'].content), {
			headers: {
				'Cache-Control': 'max-age=3600'
			}
		});
	} catch (err) {
		console.error('Récupération du gist échouée.', err);
		error(500, 'Erreur inattendue, récupération du gist échouée.');
	}
};
