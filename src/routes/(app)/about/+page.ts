import { PRETTY_NOM, PRETTY_PRENOM, SITE_TITLE } from '$lib/me';

import picSrc from '$lib/assets/me.jpg';
import type { LinkedinProfile } from '$lib/interfaces/LinkedinProfile';

export const load = async ({ fetch }) => {
	const profile = fetch('/api/linkedinProfile').then<LinkedinProfile>((res) => res.json());
	return {
		streaming: {
			profile
		},
		seo: {
			title: `à propos / ${SITE_TITLE}`,
			description: `Présentation de ${PRETTY_PRENOM} ${PRETTY_NOM}. on peut y retrouver mes détails de contact, mon CV et une brève présentation de qui je suis.`,
			image: picSrc
		}
	};
};
