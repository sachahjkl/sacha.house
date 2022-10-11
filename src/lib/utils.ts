import chroma from 'chroma-js';
import type { ProjetsResponse } from 'src/routes/api/projets/+server';
import { get } from 'svelte/store';
import { projectData } from './store';

export function capitalize(s: string) {
	return s[0].toUpperCase() + s.slice(1);
}

export const randomColor = () => {
	// 30 random hues with step of 12 degrees
	const h = Math.floor((Math.random() * 360) / 12) * 12;

	return chroma.hsl(h, 0.9, 0.6).hex();
};

export const getProjects = async () => {
	const dataCheck = get(projectData);
	if (dataCheck) return dataCheck;
	const res = await fetch('/api/projets', {
		headers: {
			'Content-Type': 'application/json'
		}
	});
	if (300 <= res.status && res.status < 200) throw new Error();
	const data: ProjetsResponse = await res.json();
	projectData.set(data);
	return data;
};
