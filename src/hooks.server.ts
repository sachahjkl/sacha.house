import { auth } from '$lib/auth';
import type { Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
	if (!auth(event.url.pathname, { clientAddress: event.getClientAddress() })) {
		return new Response(null, {
			status: 302,
			headers: {
				Location: '/'
			}
		});
	}
	const response = await resolve(event);
	return response;
};
