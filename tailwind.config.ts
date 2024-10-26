import typography from '@tailwindcss/typography';
import type { Config } from 'tailwindcss';
import defaultTheme from 'tailwindcss/defaultTheme';

export default {
	content: ['./src/**/*.{html,js,svelte,ts}'],
	theme: {
		fontFamily: {
			sans: ['monospace', ...defaultTheme.fontFamily.mono, 'Noto Color Emoji'],
			mono: ['Fira Code Medium', ...defaultTheme.fontFamily.mono, 'Noto Color Emoji'],
			serif: ['Noto Serif', ...defaultTheme.fontFamily.serif]
		},
		container: {
			center: true
		},
		extend: {
			colors: {
				bgColor: '#000000',
				bgOffColor: '#999999',
				textColor: '#DDDDDD'
			},
			typography: (theme) => ({
				DEFAULT: {
					css: {
						'--tw-prose-body': theme('colors.textColor'),
						'--tw-prose-headings': theme('colors.textColor'),
						'--tw-prose-lead': theme('colors.textColor'),
						'--tw-prose-links': theme('colors.textColor'),
						'--tw-prose-bold': theme('colors.textColor'),
						'--tw-prose-counters': theme('colors.textColor'),
						'--tw-prose-bullets': theme('colors.textColor'),
						'--tw-prose-hr': theme('colors.textColor'),
						'--tw-prose-quotes': theme('colors.textColor'),
						'--tw-prose-quote-borders': theme('colors.textColor'),
						'--tw-prose-captions': theme('colors.textColor'),
						'--tw-prose-code': theme('colors.textColor'),
						'--tw-prose-pre-code': theme('colors.bgColor'),
						'--tw-prose-pre-bg': theme('colors.textColor'),
						'--tw-prose-th-borders': theme('colors.textColor'),
						'--tw-prose-td-borders': theme('colors.textColor'),
						'--tw-prose-invert-body': theme('colors.bgColor'),
						'--tw-prose-invert-headings': theme('colors.bgColor'),
						'--tw-prose-invert-lead': theme('colors.bgColor'),
						'--tw-prose-invert-links': theme('colors.bgColor'),
						'--tw-prose-invert-bold': theme('colors.bgColor'),
						'--tw-prose-invert-counters': theme('colors.bgColor'),
						'--tw-prose-invert-bullets': theme('colors.bgColor'),
						'--tw-prose-invert-hr': theme('colors.bgColor'),
						'--tw-prose-invert-quotes': theme('colors.bgColor'),
						'--tw-prose-invert-quote-borders': theme('colors.bgColor'),
						'--tw-prose-invert-captions': theme('colors.bgColor'),
						'--tw-prose-invert-code': theme('colors.bgColor'),
						'--tw-prose-invert-pre-code': theme('colors.textColor'),
						'--tw-prose-invert-pre-bg': theme('colors.bgColor'),
						'--tw-prose-invert-th-borders': theme('colors.bgColor'),
						'--tw-prose-invert-td-borders': theme('colors.bgColor'),
						pre: {
							backgroundColor: theme('colors.bgColor'),
							color: theme('colors.textColor'),
							borderWidth: '2px',
							scrollBarWidth: 'thin',
							borderRadius: 0
						}
					}
				}
			})
		}
	},
	plugins: [typography]
} as Config;
