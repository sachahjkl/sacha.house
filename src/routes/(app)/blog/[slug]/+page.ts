import { GET_POST } from '$lib/queries';
import { GraphQLClient } from 'graphql-request';
import type { Post } from '$lib/interfaces/Post';
import { SITE_TITLE } from '$lib/me';
import { env } from '$env/dynamic/public';
import { error } from '@sveltejs/kit';

export const load = async ({ params, url }) => {
	const getPost = async () => {
		try {
			const clientGL = new GraphQLClient(env.PUBLIC_HYGRAPH_API_ENDPOINT);
			const data: { post: Post } = await clientGL.request(GET_POST, { slug: params.slug });
			const post = data.post;

			if (!post) {
				error(404, 'Poste introuvable 😔.');
			}
			return post;
		} catch (err) {
			console.error('Erreur à la récupération du post.', { err });
			error(500, 'Erreur à la récupération du poste 😔.');
		}
	};
	const post = getPost();

	return {
		post: await post,
		seo: {
			title: await post.then((post) => `${post.title} / ${SITE_TITLE}`),
			description: await post.then((post) =>
				post.content.text.length > 180
					? `${post.content.text.substring(0, 180)}...`
					: post.content.text
			),
			url: url.toString()
		}
	};
};
