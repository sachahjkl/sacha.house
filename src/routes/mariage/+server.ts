import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async () => {
	redirect(302, '/Patricia_&_Sacha_Invitation.pdf');
};
