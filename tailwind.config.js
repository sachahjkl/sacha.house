import tailwindTypography from '@tailwindcss/typography';
import defaultTheme from 'tailwindcss/defaultTheme';

/** @type {import('tailwindcss').Config} */
export default {
	content: ['./src/routes/**/*.{svelte,js,ts}', './src/lib/**/*.{svelte,js,ts}'],
	theme: {
		fontFamily: {
			sans: ['monospace', ...defaultTheme.fontFamily.mono, 'Noto Color Emoji'],
			mono: ['Fira Code Medium', ...defaultTheme.fontFamily.mono, 'Noto Color Emoji']
		},
		container: {
			center: true
		},
		extend: {
			colors: {
				bgColor: '#000000',
				bgOffColor: '#999999',
				textColor: '#DDDDDD'
			}
		},

		plugins: [tailwindTypography]
	}
};
