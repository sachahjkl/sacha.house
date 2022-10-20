import type { RequestHandler } from './$types';
import { getCounter } from '$lib/countapi';

export const GET: RequestHandler = async ({ fetch }) => {
	const visites = await getCounter(fetch);
	return new Response(visites.toString());
};
