import { SITE_TITLE } from '$lib/me';

export const load = async () => {
	// const visites = fetch('/api/visites')
	// 	.then((val) => val.text())
	// 	.then((val) => Number(val));
	return {
		// visites,
		seo: {
			title: `home / ${SITE_TITLE}`
		}
	};
};
