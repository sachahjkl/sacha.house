import type { ProjetsResponse } from 'src/routes/api/projets/+server';
import { writable } from 'svelte/store';

export const projectData = writable(null as ProjetsResponse | null);
