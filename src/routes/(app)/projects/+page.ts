import type { ProjetsResponse } from '$lib/interfaces/Project';
import { SITE_TITLE } from '$lib/me';

export const load = async ({ fetch }) => {
	const projects = fetch('/api/projets')
		.then<ProjetsResponse>((res) => res.json())
		.catch<ProjetsResponse>(() => ({ github: [], gitlab: [] }));
	return {
		streaming: {
			projects
		},
		seo: {
			title: `projects / ${SITE_TITLE}`,
			description: 'Mes projets personnels'
		}
	};
};
