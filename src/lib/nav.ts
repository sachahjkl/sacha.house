import { derived, writable } from 'svelte/store';
import { auth } from './auth';

export interface NavItem {
	icon: string;
	title: string;
	pathname: string;
	// access: RouteAccess;
}

const defaultNavItems: NavItem[] = [
	{ icon: '🏡', title: 'accueil', pathname: '/' },
	{ icon: '📁', title: 'projets', pathname: '/projets' },
	{ icon: '📜', title: 'à propos', pathname: '/a-propos' },
	{ icon: '🔒', title: 'admin', pathname: '/admin' }
];

export const getFilteredNavItems = (clientAddress = '') =>
	defaultNavItems.filter((item) => auth(item.pathname, { clientAddress }));

export const filteredNavItems = writable(getFilteredNavItems());

export const navItems = derived(filteredNavItems, (s) => s);
