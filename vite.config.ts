import type { UserConfig } from 'vite';
import { imagetools } from 'vite-imagetools';
import { sveltekit } from '@sveltejs/kit/vite';

const config: UserConfig = {
	plugins: [imagetools(), sveltekit()]
};

export default config;
