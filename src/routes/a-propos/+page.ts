import { PRETTY_NOM, PRETTY_PRENOM, SITE_TITLE } from '$lib/me';

import type { PageLoad } from './$types';
import picSrc from '$lib/assets/me.jpg';

export const load: PageLoad = async () => {
	return {
		seo: {
			title: `à propos / ${SITE_TITLE}`,
			description: `Présentation de ${PRETTY_PRENOM} ${PRETTY_NOM}. on peut y retrouver mes détails de contact, mon CV et une brève présentation de qui je suis.`,
			image: picSrc
		}
	};
};
