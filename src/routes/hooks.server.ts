import { auth } from '$lib/auth';
import { filteredNavItems, getFilteredNavItems } from '$lib/nav';
import { redirect, type Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
	const address = event.getClientAddress();
	console.log('adresse : ', address);
	filteredNavItems.set(getFilteredNavItems(address));
	if (!auth(event.url.pathname, { clientAddress: address })) return redirect(302, '/');
	const response = await resolve(event);
	return response;
};
