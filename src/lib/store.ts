// import { MaybeAsync, Maybe } from 'purify-ts';
// import { writable } from 'svelte/store';
// import { getProjects } from './utils';

import type { ProjetsResponse } from 'src/routes/projets/+server';
import { writable } from 'svelte/store';

// const maybeProjects = MaybeAsync(async () => {
// 	try {
// 		const projects = await getProjects();
// 		return projects;
// 	} catch (error) {
// 		return Maybe.empty();
// 	}
// });

export const projectData = writable(null as ProjetsResponse | null);
