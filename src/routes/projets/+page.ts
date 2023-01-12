import type { PageLoad } from './$types';
import type { ProjetsResponse } from '$lib/interfaces/Project';
import { SITE_TITLE } from '$lib/me';

export const load = (async ({ fetch }) => {
	const projects: Promise<ProjetsResponse> = fetch('/api/projets').then((res) => res.json());
	return {
		projects,
		seo: {
			title: `projets / ${SITE_TITLE}`,
			description: 'Mes projets personnels'
		}
	};
}) satisfies PageLoad;
