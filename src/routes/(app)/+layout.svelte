<script lang="ts">
	import { page } from '$app/stores';
	import '$lib/app.css';
	import faviconFallback from '$lib/assets/favicon_shadow.png?w=16&imagetools';
	import {
		default as faviconAvif,
		default as faviconWebp
	} from '$lib/assets/favicon_shadow.png?w=16;400;800&format=avif&as=srcset&imagetools';
	import Footer from '$lib/components/Footer.svelte';
	import Header from '$lib/components/Header.svelte';
	import { PRETTY_NOM, PRETTY_PRENOM, SITE_TITLE } from '$lib/me';
	import { addSnow, isChristmas } from '$lib/utils';
	import { onMount } from 'svelte';
	import type { LayoutServerData } from './$types';

	export let data: LayoutServerData;

	onMount(() => {
		if (isChristmas()) {
			addSnow(document);
		}

	});

	const TITLE = SITE_TITLE;
	const DESCRIPTION = `Le site web personnel de ${PRETTY_PRENOM} ${PRETTY_NOM}`;
	const IMAGE = '/favicon_shadow.png';
	const AUTHOR = `${PRETTY_PRENOM} ${PRETTY_NOM}`;

</script>

<svelte:head>
	<title>{$page.data.seo?.title || TITLE}</title>

	<meta name="og:title" content={$page.data.seo?.title || TITLE} />
	<meta name="twitter:title" content={$page.data.seo?.title || TITLE} />

	<meta name="description" content={$page.data.seo?.description || DESCRIPTION} />
	<meta name="og:description" content={$page.data.seo?.description || DESCRIPTION} />
	<meta name="twitter:description" content={$page.data.seo?.description || DESCRIPTION} />

	<meta name="twitter:image" content={$page.data.seo?.image || IMAGE} />
	<meta property="og:image" content={$page.data.seo?.image || IMAGE} />

	<meta
		name="keywords"
		content="Blog, Programmation, Programming, Portfolio, Personal, Personnel"
	/>
	<meta name="generator" content="SvelteKit" />
	<meta property="og:locale" content="fr_FR" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="author" content={$page.data.seo?.author || AUTHOR} />
</svelte:head>

<Header activePagePathname={$page.url.pathname} navItems={data.navItems} />

<main class="p-3 max-w-5xl m-auto pb-16">
	<slot><!-- optional fallback --></slot>
</main>

<Footer commitHash={data.commitHash}>
	<a href="/" data-sveltekit-preload-data>
		<picture>
			<source srcset={faviconAvif} type="image/avif" />
			<source srcset={faviconWebp} type="image/webp" />
			<img class="favicon" src={faviconFallback} height="1em" width="1em" alt="favicon" />
		</picture>
	</a>
</Footer>

<style lang="postcss">

	img.favicon {
		@apply inline-block align-text-top h-[1em] w-[1em];
	}
</style>
