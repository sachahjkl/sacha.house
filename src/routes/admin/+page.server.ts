import { SECRET_PROXYCURL_BEARER_TOKEN } from '$env/static/private';
import { PUBLIC_PROXYCURL_API_ENDPOINT } from '$env/static/public';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, getClientAddress }) => {
	let credit_balance = 0;
	console.log(`${PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/credit-balance`);
	try {
		const res = await fetch(`${PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/credit-balance`, {
			headers: {
				Authorization: `Bearer ${SECRET_PROXYCURL_BEARER_TOKEN}`
			},
			mode: 'cors'
		});

		({ credit_balance } = (await res.json()) as { credit_balance: number });
	} catch (error) {
		console.error("Echec de la récupération du crédit restant por l'api ProxyCURL");
	}
	// const clientAddress = getClientAddress();
	// if (!auth(url.pathname, { clientAddress })) throw redirect(302, '/');
	return {
		credit_balance,
		ip: getClientAddress()
	};
};
