import type { ProjetsResponse } from './interfaces/Project';
import { writable } from 'svelte/store';

export const projectData = writable(null as ProjetsResponse | null);
