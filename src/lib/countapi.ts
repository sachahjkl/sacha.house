import type { Result } from 'countapi-js';

export const countAPIConfig = {
	namespace: 'sacha.house',
	key: 'visites'
};

export const updateCounter = async (fetch: typeof window.fetch, amount = 1) => {
	try {
		const { key, namespace } = countAPIConfig;
		const result: Result = await fetch(
			`https://api.countapi.xyz/update/${namespace}/${key}?amount=${amount}`
		).then((data) => data.json());

		console.info('Compteur de visites incrémenté !', result.value);

		return result.value;
	} catch (error) {
		console.error("Echec lors de l'incrémentation du compteur de visites.", { error });
		return -1;
	}
};

export const getCounter = async (fetch: typeof window.fetch) => {
	try {
		const { key, namespace } = countAPIConfig;
		const result: Result = await fetch(`https://api.countapi.xyz/get/${namespace}/${key}`).then(
			(data) => data.json()
		);

		console.info('Compteur de visites consulté !', result.value);

		return result.value;
	} catch (error) {
		console.error('Echec lors de la récupération du compteur de visites.', { error });
		return -1;
	}
};
