import type { Result } from 'countapi-js';

export const countAPIConfig = {
	namespace: 'sacha.house',
	key: 'visites'
};

export const updateCounter = async (fetch: typeof window.fetch, amount = 1) => {
	try {
		const { key, namespace } = countAPIConfig;
		const result = (await fetch(
			`https://api.countapi.xyz/update/${namespace}/${key}?amount=${amount}`
		).then((data) => data.json())) as Result;

		return result.value;
	} catch (error) {
		console.error("Echec lors de l'incrémentation du compteur de visites.", { error });
		return -1;
	}
};
