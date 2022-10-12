import { env } from '$env/dynamic/private';

const ADMIN_ALWAYS_OFF = false;
const DEFAULT_IPS = ['127.0.0.1', '::1'];

export enum Visibility {
	public,
	admin
}

export interface AccessRule {
	pathname: RegExp;
	visibility: Visibility[];
}

const rules: AccessRule[] = [
	{
		pathname: /^\/(api\/)?admin\/?.*$/,
		visibility: [Visibility.admin]
	}
];

const isAuthorizedIP = (ip = '255.255.255.255') => {
	const IPs = (JSON.parse(env.SECRET_ADMIN_IPS) as string[]).map((item) => item.trim());
	return !ADMIN_ALWAYS_OFF && [...IPs, ...DEFAULT_IPS].includes(ip);
};

interface AuthParams {
	clientAddress?: string;
}

export const auth = (pathname: string, params: AuthParams): boolean => {
	const rule = rules.find((rule) => pathname.match(rule.pathname));
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
