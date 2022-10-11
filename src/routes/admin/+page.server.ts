import { SECRET_PROXYCURL_BEARER_TOKEN } from '$env/static/private';
import { PUBLIC_PROXYCURL_API_ENDPOINT } from '$env/static/public';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch }) => {
	console.log(`${PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/credit-balance`);
	const res = await fetch(`${PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/credit-balance`, {
		headers: {
			Authorization: `Bearer ${SECRET_PROXYCURL_BEARER_TOKEN}`
		},
		mode: 'cors'
	});

	const { credit_balance } = (await res.json()) as { credit_balance: number };
	// const clientAddress = getClientAddress();
	// if (!auth(url.pathname, { clientAddress })) throw redirect(302, '/');
	return {
		credit_balance
	};
};
