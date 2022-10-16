import type { LinkedinProfile } from './interfaces/LinkedinProfile';
import type { ProjetsResponse } from './interfaces/Project';
import { writable } from 'svelte/store';

export const projectData = writable(null as ProjetsResponse | null);
export const profile = writable(null as LinkedinProfile | null);
