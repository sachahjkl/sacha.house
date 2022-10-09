const daisyui = require('daisyui');
const tailwindTypography = require('@tailwindcss/typography');

/** @type {import('tailwindcss').Config} */
module.exports = {
	content: ['./src/routes/**/*.{svelte,js,ts}', './src/lib/**/*.{svelte,js,ts}'],
	theme: {
		extend: {}
	},

	plugins: [tailwindTypography, daisyui],
	daisyui: {
		styled: true,
		// themes: true,
		// base: true,
		// utils: true,
		// logs: true,
		// rtl: false,
		// prefix: '',
		darkTheme: 'dark'
	}
};
