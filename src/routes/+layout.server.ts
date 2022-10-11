import type { LayoutServerLoad } from './$types';
import { getAuthorizedNavItems } from '$lib/nav';
import { countAPIConfig } from '$lib/constants';
import type { Result } from 'countapi-js';
import { redirect } from '@sveltejs/kit';
import { auth } from '$lib/auth';

export const load: LayoutServerLoad = async ({ fetch, getClientAddress, url }) => {
	const clientAddress = getClientAddress();
	if (!auth(url.pathname, { clientAddress })) throw redirect(302, '/');

	const { key, namespace } = countAPIConfig;
	let visites = -1;
	try {
		const participants: Promise<Result> = (
			await fetch(`https://api.countapi.xyz/hit/${namespace}/${key}`)
		).json();
		visites = (await participants).value;
	} catch {
		console.log("erreur à l'incrémentation du compteur de visites.");
	}
	return {
		navItems: getAuthorizedNavItems(clientAddress),
		visites
	};
};
