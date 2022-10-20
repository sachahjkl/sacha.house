import type { Gender } from './interfaces/Person';

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
