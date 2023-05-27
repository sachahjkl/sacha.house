import { text } from '@sveltejs/kit';

export const GET = async ({ fetch }) => {
	return text(await fetch('/api/ip').then((res) => res.text()));
};
