import type { ProjetsResponse } from '$lib/interfaces/Project';
import { MOI } from '$lib/me';

export const load = async ({ fetch }) => {
	const projects = fetch('/api/projets')
		.then<ProjetsResponse>((res) => res.json())
		.catch<ProjetsResponse>(() => ({ github: [], gitlab: [] }));
	return {
		projects: projects,
		seo: {
			title: `projects / ${MOI.siteTitle}`,
			description: 'Mes projets personnels'
		}
	};
};
