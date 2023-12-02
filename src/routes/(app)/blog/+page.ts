import { env } from '$env/dynamic/public';
import type { ListedPost } from '$lib/interfaces/Post';
import { SITE_TITLE } from '$lib/me';
import { GET_POSTS } from '$lib/queries';
import { error } from '@sveltejs/kit';
import { GraphQLClient } from 'graphql-request';

export const load = async () => {
	const getPosts = async () => {
		try {
			const clientGL = new GraphQLClient(env.PUBLIC_HYGRAPH_API_ENDPOINT);
			const posts = await clientGL
				.request(GET_POSTS)
				.then((data) => (data as { posts: ListedPost[] }).posts);
			if (!posts.length) {
				throw error(404, 'Postes introuvables !');
			}
			return posts;
		} catch (err) {
			console.error('Erreur à la récupération des posts.', { err });
		}
		return [] as ListedPost[];
	};

	return {
		streaming: {
			posts: getPosts()
		},
		seo: {
			title: `blog / ${SITE_TITLE}`,
			description:
				"Mon blog dans lequel je posterai (rarement) des sujets portant souvent sur l'informatique."
		}
	};
};
