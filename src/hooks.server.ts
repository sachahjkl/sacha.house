import type { HTTPMethod } from '$lib/interfaces/HTTP';
import type { Handle } from '@sveltejs/kit';
import { auth } from '$lib/auth';

export const handle: Handle = async ({ event, resolve }) => {
	if (
		!auth(event.url.pathname, {
			clientAddress: event.getClientAddress(),
			method: event.request.method as HTTPMethod
		})
	) {
		return new Response(null, {
			status: 401,
			headers: {
				Location: '/'
			},
			statusText: 'Pas autorisé à exécuter cette action.'
		});
	}
	const response = await resolve(event);
	return response;
};
