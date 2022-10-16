import type { ProjetsResponse } from 'src/routes/api/projets/+server';
import { get } from 'svelte/store';
import { projectData } from './store';

export function capitalize(s: string) {
	return s[0].toUpperCase() + s.slice(1);
}

export const randomColorHSL = () => {
	// 30 random hues with step of 12 degrees
	const h = Math.floor((Math.random() * 360) / 12) * 12;

	return [h, 0.9, 0.6];
};

export const getProjects = async () => {
	const dataCheck = get(projectData);
	if (dataCheck) return dataCheck;
	const res = await fetch('/api/projets', {
		headers: {
			'Content-Type': 'application/json'
		}
	});
	if (!res.ok) throw new Error('bourbier pas de projet khouya');
	const data: ProjetsResponse = await res.json();
	projectData.set(data);
	return data;
};
