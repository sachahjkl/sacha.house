import type { HTTPMethod } from './interfaces/HTTP';
import { env } from '$env/dynamic/private';

const ADMIN_ALWAYS_OFF = false;
const DEFAULT_IPS = ['127.0.0.1', '::1'];

export enum Visibility {
	public,
	admin
}

export interface AccessRule {
	pathname: RegExp;
	methods?: HTTPMethod[];
	visibility: Visibility[];
}

const rules: AccessRule[] = [
	{
		pathname: /^\/(api\/)?admin\/?.*$/,
		visibility: [Visibility.admin]
	},
	{
		pathname: /^\/linkedinProfile\/?$/,
		visibility: [Visibility.admin],
		methods: ['PATCH']
	}
];

const isAuthorizedIP = (ip = '255.255.255.255') => {
	const IPs = (JSON.parse(env.SECRET_ADMIN_IPS) as string[]).map((item) => item.trim());
	return !ADMIN_ALWAYS_OFF && [...IPs, ...DEFAULT_IPS].includes(ip);
};

interface AuthParams {
	clientAddress?: string;
	method?: HTTPMethod;
}

const getRule = (pathname: string, params: AuthParams = { method: 'GET' }) => {
	const rule = rules.find((rule) => {
		const pathnameCheck = pathname.match(rule.pathname);
		// on compare les méthodes si une méthode est contrôlée par l'AccessRule,
		// sinon OK
		const methodCheck =
			!rule.methods || !params.method || (params.method && rule.methods.includes(params.method));

		return pathnameCheck && methodCheck;
	});
	return rule;
};

export const auth = (pathname: string, params: AuthParams): boolean => {
	const defaultParams = { method: 'GET' };
	params = { ...defaultParams, ...params } as AuthParams;
	const rule = getRule(pathname, params);
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
