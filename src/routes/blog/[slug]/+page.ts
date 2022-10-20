import { GET_POST } from '$lib/queries';
import { GraphQLClient } from 'graphql-request';
import { PUBLIC_HYGRAPH_API_ENDPOINT } from '$env/static/public';
import type { PageLoad } from './$types';
import type { Post } from '$lib/interfaces/Post';
import { SITE_TITLE } from '$lib/me';
import { error } from '@sveltejs/kit';

export const load: PageLoad = async ({ params, url }) => {
	const getPost = async () => {
		try {
			const clientGL = new GraphQLClient(PUBLIC_HYGRAPH_API_ENDPOINT);
			const data: { post: Post } = await clientGL.request(GET_POST, { slug: params.slug });
			const post = data.post;

			if (!post) {
				throw error(404, 'Poste introuvable 😔.');
			}
			return post;
		} catch (err) {
			console.error('Erreur à la récupération du post.', { err });
			throw error(500, 'Erreur à la récupération du poste 😔.');
		}
	};
	const post = getPost();

	const promise = post.then((post) => ({
		excerpt:
			post.content.text.length > 180
				? `${post.content.text.substring(0, 180)}...`
				: post.content.text,
		title: `${post.title} / ${SITE_TITLE}`
	}));

	return {
		post,
		seo: {
			title: await promise.then((val) => val.title),
			description: await promise.then((val) => val.excerpt),
			url: url.toString()
		}
	};
};
