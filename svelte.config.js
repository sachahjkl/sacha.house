// import adapter from '@sveltejs/adapter-auto';

import adapter from '@sveltejs/adapter-netlify';
import preprocess from 'svelte-preprocess';

// import adapter from '@sveltejs/adapter-node';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	// Consult https://github.com/sveltejs/svelte-preprocess
	// for more information about preprocessors

	preprocess: preprocess({
		postcss: true
	}),

	kit: {
		adapter: adapter({
			edge: false,
			split: true
		}),
		// adapter: adapter({ precompress: true }),
		version: {
			name: Date.now().toString()
		}
	}
};

export default config;
