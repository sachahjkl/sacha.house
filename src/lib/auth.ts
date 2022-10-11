import { SECRET_ADMIN_IPS } from '$env/static/private';

export enum RouteAccess {
	public,
	admin
}

export interface AccessRule {
	pathname: string;
	access: RouteAccess[];
}

const rules: AccessRule[] = [
	{
		pathname: '/admin',
		access: [RouteAccess.admin]
	}
];

const isAuthorizedIP = (ip = '255.255.255.255') =>
	SECRET_ADMIN_IPS.split(',')
		.map((item) => item.trim())
		.includes(ip);

interface AuthParams {
	clientAddress?: string;
}

export const auth = (pathname: string, params: AuthParams): boolean => {
	const rule = rules.find((rule) => rule.pathname === pathname);
	let access = false;
	if (!rule) return true;
	if (rule.access.includes(RouteAccess.admin)) access = isAuthorizedIP(params.clientAddress);
	if (rule.access.includes(RouteAccess.public)) access = true;
	console.info(
		`authentification ${access ? 'autorisé' : 'refusé'} pour la route "${pathname}"`,
		params
	);
	return access;
};
