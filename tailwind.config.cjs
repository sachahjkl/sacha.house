const daisyui = require('daisyui');
const tailwindTypography = require('@tailwindcss/typography');
const tailwindLineClamp = require('@tailwindcss/line-clamp');
const defaultTheme = require('tailwindcss/defaultTheme');

/** @type {import('tailwindcss').Config} */
module.exports = {
	content: ['./src/routes/**/*.{svelte,js,ts}', './src/lib/**/*.{svelte,js,ts}'],
	theme: {
		fontFamily: {
			sans: ['Inter', 'Inter-fallback', ...defaultTheme.fontFamily.sans]
		},
		container: {
			center: true
		}
	},

	plugins: [tailwindLineClamp, tailwindTypography, daisyui],
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
