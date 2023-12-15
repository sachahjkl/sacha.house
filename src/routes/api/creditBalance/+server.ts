import { env as envPriv } from '$env/dynamic/private';
import { env as envPub } from '$env/dynamic/public';
import { error } from '@sveltejs/kit';

export const GET = async () => {
	try {
		const res = await fetch(
			`${envPub.PUBLIC_PROXYCURL_API_ENDPOINT}/proxycurl/api/credit-balance`,
			{
				headers: {
					Authorization: `Bearer ${envPriv.PROXYCURL_BEARER_TOKEN}`
				}
			}
		);
		const credit_balance = await res
			.json()
			.then((value: { credit_balance: number }) => value.credit_balance);
		return new Response(credit_balance.toString());
	} catch (err) {
		error(500, "Echec de la récupération du crédit restant pour l'api ProxyCURL");
	}
};
