import daisyui from 'daisyui';
import defaultTheme from 'tailwindcss/defaultTheme';
import tailwindTypography from '@tailwindcss/typography';

/** @type {import('tailwindcss').Config} */
export default {
	content: ['./src/routes/**/*.{svelte,js,ts}', './src/lib/**/*.{svelte,js,ts}'],
	theme: {
		fontFamily: {
			sans: ['Inter', 'Inter-fallback', 'Noto Color Emoji', ...defaultTheme.fontFamily.sans]
		},
		container: {
			center: true
		}
	},

	plugins: [tailwindTypography, daisyui],
	daisyui: {
		styled: true
		// themes: true,
		// base: true,
		// utils: true,
		// logs: true,
		// rtl: false,
		// prefix: '',
		// darkTheme: 'dark'
	}
};
