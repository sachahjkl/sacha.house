import { error } from '@sveltejs/kit';

const drinks = ['tea', 'coffee'];

export async function load({ url }) {
	let brewMessage;
	const drink = url.searchParams.get('drink');
	switch (drink) {
		case null:
			break;
		case 'tea':
		case 'thé':
			brewMessage = { text: `Here, have a nice cup of ${drink} : `, emoji: '🍵' };
			break;
		case 'coffee':
		case 'café':
			return error(418, {
				message:
					'Did you really think a teapot could brew you coffee ??\nare you some kind of lunatic or something ?'
			});
		default:
			brewMessage = { text: `What kind of a drink is "${drink}" ???`, emoji: '🤮' };
	}
	return {
		brewMessage,
		brewTypes: drinks,
		spewage: (Math.random() + 1).toString(36).substring(7)
	};
}
