import { auth } from './auth';

export interface NavItem {
	icon: string;
	title: string;
	pathname: string;
}

const defaultNavItems: NavItem[] = [
	{ icon: '🏡', title: 'accueil', pathname: '/' },
	{ icon: '📁', title: 'projets', pathname: '/projets' },
	{ icon: '📜', title: 'à propos', pathname: '/a-propos' },
	{ icon: '🔒', title: 'admin', pathname: '/admin' }
];

export const getAuthorizedNavItems = (clientAddress = '') =>
	defaultNavItems.filter((item) => auth(item.pathname, { clientAddress }));
