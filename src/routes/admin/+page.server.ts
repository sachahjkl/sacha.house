import type { PageServerLoad } from './$types';
import { SITE_TITLE } from '$lib/constants';

export const load: PageServerLoad = async ({ getClientAddress }) => {
	return {
		ip: getClientAddress(),
		seo: {
			title: `admin / ${SITE_TITLE}`,
			description: "Panneau d'administration du site."
		}
	};
};
