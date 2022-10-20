import type { RequestHandler } from './$types';
import { getCounter } from '$lib/countapi';

export const GET: RequestHandler = async () => {
	const visites = await getCounter();
	return new Response(visites.toString());
};
