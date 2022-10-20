import type { PageLoad } from './$types';
import { SITE_TITLE } from '$lib/me';

export const load: PageLoad = async ({ fetch }) => {
	const visites = fetch('/api/visites')
		.then((val) => val.text())
		.then((val) => Number(val));
	return {
		visites,
		seo: {
			title: `accueil / ${SITE_TITLE}`
		}
	};
};
