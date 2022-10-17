import { GET_POST } from '$lib/queries';
import { GraphQLClient } from 'graphql-request';
import { PUBLIC_HYGRAPH_API_ENDPOINT } from '$env/static/public';
import type { PageServerLoad } from './$types';
import type { Post } from '$lib/interfaces/Post';
import { SITE_TITLE } from '$lib/constants';
import { redirect } from '@sveltejs/kit';

export const load: PageServerLoad = async ({ params }) => {
	let post: Post = {} as Post;
	try {
		const clientGL = new GraphQLClient(PUBLIC_HYGRAPH_API_ENDPOINT, {
			fetch
		});
		const data: { post: Post } = await clientGL.request(GET_POST, { slug: params.slug });
		if (!data.post) {
			throw redirect(302, '/blog');
		}
		post = data.post;
	} catch (error) {
		console.error('Erreur à la récupération du post.');
	}

	const excerpt =
		post.content.html.length > 180
			? `${post.content.html.substring(0, 180)}...`
			: post.content.html;

	return {
		post,
		seo: {
			title: `${post.title} / ${SITE_TITLE}`,
			description: excerpt
		}
	};
};
