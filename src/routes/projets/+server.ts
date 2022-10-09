import type { RequestHandler } from './$types';

import { PUBLIC_GITHUB_API_ENDPOINT, PUBLIC_GITLAB_API_ENDPOINT } from '$env/static/public';
import { MOI } from '$lib/constants';
import { GET_PROJECTS_GITHUB, GET_PROJECTS_GITLAB } from '$lib/queries';
import { SECRET_GITHUB_BEARER_TOKEN, SECRET_GITLAB_BEARER_TOKEN } from '$env/static/private';
import { makeGqlBody } from '$lib/queries';
import { json } from '@sveltejs/kit';

export const GET: RequestHandler = async ({ fetch }) => {
	const promiseGH = fetch(PUBLIC_GITHUB_API_ENDPOINT, {
		method: 'POST',
		body: makeGqlBody(GET_PROJECTS_GITHUB, { username: MOI.username }),
		headers: {
			Authorization: `Bearer ${SECRET_GITHUB_BEARER_TOKEN}`,
			'Content-Type': 'application/json'
		}
	});
	const promiseGL = fetch(PUBLIC_GITLAB_API_ENDPOINT, {
		method: 'POST',
		body: makeGqlBody(GET_PROJECTS_GITLAB, { username: MOI.username }),
		headers: {
			Authorization: `Bearer ${SECRET_GITLAB_BEARER_TOKEN}`,
			'Content-Type': 'application/json'
		}
	});
	const [resGH, resGL] = await Promise.all([promiseGH, promiseGL]);

	return json({
		github: (await resGH.json()).data,
		gitlab: (await resGL.json()).data
	});
};
