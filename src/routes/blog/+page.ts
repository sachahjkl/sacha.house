import { GET_POSTS } from '$lib/queries';
import { GraphQLClient } from 'graphql-request';
import type { ListedPost } from '$lib/interfaces/Post';
import { PUBLIC_HYGRAPH_API_ENDPOINT } from '$env/static/public';
import type { PageLoad } from './$types';
import { SITE_TITLE } from '$lib/me';
import { error } from '@sveltejs/kit';

export const load: PageLoad = async ({ fetch }) => {
	let posts: ListedPost[] = [];
	fetch;
	try {
		const clientGL = new GraphQLClient(PUBLIC_HYGRAPH_API_ENDPOINT, {
			headers: {
				'Content-Type': 'application/json',
				Accept: 'application/json'
			}
		});
		posts = await clientGL.request(GET_POSTS).then((data: { posts: ListedPost[] }) => data.posts);
	} catch (err) {
		console.error('Erreur à la récupération des posts.', { err });
	}

	if (!posts.length) {
		throw error(404, 'Postes introuvables !');
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
