import { auth } from './auth';

export interface NavItem {
	icon: string;
	title: string;
	pathname: string;
}

const defaultNavItems: NavItem[] = [
	{ icon: '🏡', title: 'home', pathname: '/' },
	{ icon: '📁', title: 'projects', pathname: '/projects' },
	{ icon: '📰', title: 'blog', pathname: '/blog' },
	{ icon: '📜', title: 'about', pathname: '/about' },
	{ icon: '🔒', title: 'admin', pathname: '/admin' }
];

export const getAuthorizedNavItems = (clientAddress = '') =>
	defaultNavItems.filter((item) => auth(item.pathname, { clientAddress }));
