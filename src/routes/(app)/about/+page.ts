import { MOI } from '$lib/me';

import picSrc from '$lib/assets/me.jpg';

export const load = ({ fetch }) => {
	const profile = fetch('/api/linkedinProfile').then((r) => r.json());
	return {
		profile,
		seo: {
			title: `about / ${MOI.siteTitle}`,
			description: `Présentation de ${MOI.prettyPrenom} ${MOI.prettyNom}. on peut y retrouver mes détails de contact, mon CV et une brève présentation de qui je suis.`,
			image: picSrc
		}
	};
};
