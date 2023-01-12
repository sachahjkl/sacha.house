import { PUBLIC_PROXYCURL_API_ENDPOINT } from '$env/static/public';
import type { RequestHandler } from './$types';
import { SECRET_PROXYCURL_BEARER_TOKEN } from '$env/static/private';
import { error } from '@sveltejs/kit';

export const GET = (async () => {
	try {
		const res = await fetch(`${PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/credit-balance`, {
			headers: {
				Authorization: `Bearer ${SECRET_PROXYCURL_BEARER_TOKEN}`
			}
		});
		const credit_balance = await res
			.json()
			.then((value: { credit_balance: number }) => value.credit_balance);
		return new Response(credit_balance.toString());
	} catch (err) {
		throw error(500, "Echec de la récupération du crédit restant pour l'api ProxyCURL");
	}
}) satisfies RequestHandler;
