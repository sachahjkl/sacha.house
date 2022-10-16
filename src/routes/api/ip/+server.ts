import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ getClientAddress }) => {
	return new Response(getClientAddress());
};
