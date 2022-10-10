import type { LayoutLoad } from './$types';
import { countAPIConfig } from '$lib/constants';
import type { Result } from 'countapi-js';

export const load: LayoutLoad = async ({ fetch }) => {
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
		visites
	};
};
