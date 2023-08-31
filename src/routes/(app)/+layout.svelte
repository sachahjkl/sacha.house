<script lang="ts">
	import { navigating, page } from '$app/stores';
	import '$lib/app.css';
	import { onMount } from 'svelte';
// import { fly } from 'svelte/transition';
	import { PUBLIC_NETLIFY_SITE_ID } from '$env/static/public';
	import { MOI, PRETTY_NOM, PRETTY_PRENOM, SITE_TITLE } from '$lib/me';
	import { addSnow, capitalize, isChristmas } from '$lib/utils';
// import { env } from '$env/dynamic/public';
	import faviconFallback from '$lib/assets/favicon_shadow.png?w=16&imagetools';
	import {
		default as faviconAvif,
		default as faviconWebp
	} from '$lib/assets/favicon_shadow.png?w=16;400;800&format=avif&as=srcset&imagetools';
	import Footer from '$lib/components/Footer.svelte';
	import Header from '$lib/components/Header.svelte';
	import { SvelteToast } from '@zerodevx/svelte-toast';
	import nProgress from 'nprogress';
	import type { LayoutServerData } from './$types';

	export let data: LayoutServerData;

	// const useIntro: boolean = JSON.parse(env.PUBLIC_USE_INTRO || 'true');
	// let doIntro = !useIntro;

	onMount(() => {
		nProgress.configure({ easing: 'ease', speed: 500 });
		if (isChristmas()) {
			addSnow(document);
		}

		return () => {
			nProgress.done();
			nProgress.remove();
		};

		// doIntro = true;
	});

	const TITLE = SITE_TITLE;
	const DESCRIPTION = `Le site web personnel de ${PRETTY_PRENOM} ${PRETTY_NOM}`;
	const IMAGE = '/favicon_shadow.png';
	const AUTHOR = `${PRETTY_PRENOM} ${PRETTY_NOM}`;

	$: {
		if ($navigating) {
			nProgress.start();
		} else {
			nProgress.done();
		}
	}
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

<Header activePagePathname={$page.url.pathname} navItems={data.navItems}>
	<a slot="brand" href="/" data-sveltekit-preload-data>
		<picture>
			<source srcset={faviconAvif} type="image/avif" />
			<source srcset={faviconWebp} type="image/webp" />
			<img class="favicon" src="/favicon_shadow.png" height="1em" width="1em" alt="favicon" />
		</picture>
		{MOI.prenom.substring(1)}
		{capitalize(MOI.nom)}
	</a>
</Header>

<!-- {#if doIntro} -->
<main>
	<slot><!-- optional fallback --></slot>
</main>

<Footer commitHash={data.commitHash} netlifyID={PUBLIC_NETLIFY_SITE_ID}>
	<a slot="brand" href="/" data-sveltekit-preload-data>
		<picture>
			<source srcset={faviconAvif} type="image/avif" />
			<source srcset={faviconWebp} type="image/webp" />
			<img class="favicon" src={faviconFallback} height="1em" width="1em" alt="favicon" />
		</picture>
	</a>
</Footer>
<!-- {/if} -->
<SvelteToast options={{ duration: 2000 }} />

<style lang="postcss">
	main {
		@apply max-w-5xl m-auto mt-6 p-4;
	}

	img.favicon {
		@apply inline-block align-text-top h-[1em] w-[1em];
	}
</style>
