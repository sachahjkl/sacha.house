import type { LayoutLoad } from './$types';
import { countAPIConfig } from '$lib/constants';
import type { Result } from 'countapi-js';

export const load: LayoutLoad = async ({ fetch }) => {
	const { key, namespace } = countAPIConfig;
	const participants: Promise<Result> = (
		await fetch(`https://api.countapi.xyz/hit/${namespace}/${key}`)
	).json();

	return {
		participants
	};
};
