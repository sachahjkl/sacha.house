// import { powershell } from '$lib/serverUtils';
import type { RequestHandler } from './$types';
import { SECRET_PROXYCURL_BEARER_TOKEN } from '$env/static/private';
import { PUBLIC_PROXYCURL_API_ENDPOINT } from '$env/static/public';
import { error } from '@sveltejs/kit';

// const GET_BALANCE = `(curl -Method Get -Headers @{'Authorization' = 'Bearer ${SECRET_PROXYCURL_BEARER_TOKEN}';} ${PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/credit-balance).Content`;

export const GET: RequestHandler = async () => {
	try {
		const res = await fetch(`${PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/credit-balance`, {
			headers: {
				Authorization: `Bearer ${SECRET_PROXYCURL_BEARER_TOKEN}`
			}
		});
		const credit_balance = ((await res.json()) as { credit_balance: number }).credit_balance;
		return new Response(credit_balance.toString());
	} catch (err) {
		throw error(500, "Echec de la récupération du crédit restant por l'api ProxyCURL");
	}
};
