import { profile, projectData } from './store';

import type { Gender } from './interfaces/Person';
import type { LinkedinProfile } from './interfaces/LinkedinProfile';
import type { ProjetsResponse } from './interfaces/Project';
import { get } from 'svelte/store';

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
	const res = await fetch('/api/projets');
	if (!res.ok) throw new Error('bourbier pas de projet khouya');
	const data: ProjetsResponse = await res.json();
	projectData.set(data);
	return data;
};
export const getProfile = async () => {
	const dataCheck = get(profile);
	if (dataCheck) return dataCheck;
	const res = await fetch('/api/linkedinProfile');
	if (!res.ok) throw new Error('bourbier pas de profile khouya');
	const data: LinkedinProfile = await res.json();
	profile.set(data);
	return data;
};

export const metaDescription = (description = ' ') => `
	<meta name="og:description" content="${description}" />
	<meta name="twitter:description" content="${description}" />
	<meta name="description" content="${description}" />
`;

export const metaTitle = (title = ' ') => `
	<title>${title}</title>
	<meta name="og:title" content="${title}" />
	<meta name="twitter:title" content="${title}" />
`;

export const metaArticle = (options: { createdAt: Date; updatedAt?: Date; author: string }) => `
	<meta property="og:article:published_time" content="${options.createdAt.toISOString()}" />
	${
		options.updatedAt
			? `<meta property="og:article:modified_time" content="${options.updatedAt.toISOString()}"/>`
			: ''
	}
	<meta property="og:article:author" content="${options.author}" />
	<meta name="author" content="${options.author}" />
`;

export const metaProfile = (
	prenom = 'John',
	nom = 'Smith',
	username = 'johnsmith',
	gender: Gender = 'male'
) => `
	<meta property="og:type" content="profile" />
	<meta property="og:profile:first_name" content="${prenom}" />
	<meta property="og:profile:last_name" content="${nom}" />
	<meta property="og:profile:username" content="${username}" />
	<meta property="og:profile:gender" content="${gender}" />s
`;
