import { GET_POSTS } from '$lib/queries';
import { GraphQLClient } from 'graphql-request';
import { PUBLIC_HYGRAPH_API_ENDPOINT } from '$env/static/public';
import type { PageServerLoad } from './$types';
import type { Post } from '$lib/interfaces/Post';

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
		posts
	};
};
