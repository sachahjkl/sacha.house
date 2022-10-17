import { GET_POSTS } from '$lib/queries';
import { GraphQLClient } from 'graphql-request';
import { PUBLIC_HYGRAPH_API_ENDPOINT } from '$env/static/public';
import type { PageServerLoad } from './$types';
import type { Post } from '$lib/interfaces/Post';
import { SITE_TITLE } from '$lib/constants';

export const load: PageServerLoad = async () => {
	let posts: Post[] = [];
	try {
		const clientGL = new GraphQLClient(PUBLIC_HYGRAPH_API_ENDPOINT, {
			fetch
		});
		const data: { posts: Post[] } = await clientGL.request(GET_POSTS);
		posts = data.posts;
	} catch (error) {
		console.error('Erreur à la récupération des posts.');
	}

	return {
		posts,
		seo: {
			title: `blog / ${SITE_TITLE}`,
			description:
				"Mon blog dans lequel je posterai (rarement) des sujets portant souvent sur l'informatique."
		}
	};
};
