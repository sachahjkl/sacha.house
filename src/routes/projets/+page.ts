import type { PageLoad } from './$types';
import { SITE_TITLE } from '$lib/me';

export const load: PageLoad = async () => {
	return {
		seo: {
			title: `projets / ${SITE_TITLE}`,
			description: 'Mes projets personnels'
		}
	};
};
