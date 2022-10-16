import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ fetch }) => {
	return new Response(await fetch('/api/ip').then((res) => res.text()));
};
