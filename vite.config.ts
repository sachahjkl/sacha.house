import { SvelteKitPWA } from '@vite-pwa/sveltekit';
import type { UserConfig } from 'vite';
import { imagetools } from 'vite-imagetools';
import { sveltekit } from '@sveltejs/kit/vite';

const config: UserConfig = {
	plugins: [
		imagetools(),
		sveltekit(),
		SvelteKitPWA({
			srcDir: './src',
			registerType: 'autoUpdate',
			strategies: 'generateSW',
			scope: '/',
			base: '/',
			manifest: {
				short_name: 'sacha.house',
				name: 'sacha.house',
				description: 'Le site web personnel de Sacha FROMENT',
				display: 'standalone',
				theme_color: '#286090',
				background_color: '#ffffff',
				icons: [
					{
						src: '/maskable_icon_x48.png',
						sizes: '48x48',
						type: 'image/png'
					},
					{
						src: '/maskable_icon_x72.png',
						sizes: '72x72',
						type: 'image/png'
					},
					{
						src: '/maskable_icon_x96.png',
						sizes: '96x96',
						type: 'image/png'
					},
					{
						src: '/maskable_icon_x128.png',
						sizes: '128x128',
						type: 'image/png'
					},
					{
						src: '/maskable_icon_x192.png',
						sizes: '192x192',
						type: 'image/png'
					},
					{
						src: '/maskable_icon_x384.png',
						sizes: '384x384',
						type: 'image/png',
						purpose: 'any maskable'
					},
					{
						src: '/maskable_icon_x512.png',
						sizes: '512x512',
						type: 'image/png',
						purpose: 'any maskable'
					}
				]
			},
			workbox: {
				navigateFallbackDenylist: [/^\/admin/],
				runtimeCaching: [
					{
						urlPattern: /^https:\/\/fonts\.googleapis\.com\/.*/i,
						handler: 'CacheFirst',
						options: {
							cacheName: 'google-fonts-cache',
							expiration: {
								maxEntries: 10,
								maxAgeSeconds: 60 * 60 * 24 * 365 // <== 365 days
							},
							cacheableResponse: {
								statuses: [0, 200]
							}
						}
					},
					{
						urlPattern: /^https:\/\/fonts\.gstatic\.com\/.*/i,
						handler: 'CacheFirst',
						options: {
							cacheName: 'gstatic-fonts-cache',
							expiration: {
								maxEntries: 10,
								maxAgeSeconds: 60 * 60 * 24 * 365 // <== 365 days
							},
							cacheableResponse: {
								statuses: [0, 200]
							}
						}
					}
				]
			}
		})
	]
};

export default config;
