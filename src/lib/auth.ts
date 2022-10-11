import { env } from '$env/dynamic/private';

export enum Visibility {
	public,
	admin
}

export interface AccessRule {
	pathname: string;
	visibility: Visibility[];
}

const rules: AccessRule[] = [
	{
		pathname: '/admin',
		visibility: [Visibility.admin]
	}
];

const isAuthorizedIP = (ip = '255.255.255.255') =>
	[...env.SECRET_ADMIN_IPS.split(',').map((item) => item.trim()), '127.0.0.1', '::1'].includes(ip);

interface AuthParams {
	clientAddress?: string;
}

export const auth = (pathname: string, params: AuthParams): boolean => {
	const rule = rules.find((rule) => rule.pathname === pathname);
	let access = false;
	if (!rule) {
		access = true;
	} else {
		if (rule.visibility.includes(Visibility.admin)) access = isAuthorizedIP(params.clientAddress);
		if (rule.visibility.includes(Visibility.public)) access = true;
	}
	console.info(
		`authentification ${access ? 'autorisée' : 'refusée'} pour la route "${pathname}", params : `,
		params
	);
	return access;
};
