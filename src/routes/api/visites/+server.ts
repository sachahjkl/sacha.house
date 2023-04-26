import { getCounter } from '$lib/countapi';

export const GET = async () => {
	const visites = await getCounter();
	return new Response(visites.toString(), {
		headers: {
			'Cache-Control': 'max-age=3600'
		}
	});
};
