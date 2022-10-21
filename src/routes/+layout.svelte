<script lang="ts">
	import '$lib/app.css';
	import { page, navigating } from '$app/stores';
	import { onMount } from 'svelte';
	import { fly } from 'svelte/transition';
	import { MOI, PRETTY_NOM, PRETTY_PRENOM, SITE_TITLE } from '$lib/me';
	import { capitalize } from '$lib/utils';
	import { PUBLIC_NETLIFY_SITE_ID } from '$env/static/public';
	import { env } from '$env/dynamic/public';
	import { SvelteToast } from '@zerodevx/svelte-toast';
	import type { LayoutServerData } from './$types';
	import Header from '$lib/components/Header.svelte';
	import Footer from '$lib/components/Footer.svelte';
	import nProgress from 'nprogress';

	export let data: LayoutServerData;

	const useIntro: boolean = JSON.parse(env.PUBLIC_USE_INTRO || 'true');
	let doIntro = !useIntro;

	onMount(() => {
		nProgress.configure({ easing: 'ease', speed: 500 });
		doIntro = true;
	});
	let headerheight = 56; // default average height in pixels;

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

<Header bind:headerheight activePagePathname={$page.url.pathname} navItems={data.navItems}>
	<a slot="brand" href="/" data-sveltekit-prefetch>
		<img class="favicon" src="/favicon_shadow.png" alt="favicon" />
		{MOI.prenom.substring(1)}
		{capitalize(MOI.nom)}
	</a>
</Header>

{#if doIntro}
	<div style="--headerHeight: {headerheight}px" class="content" in:fly={{ y: -50 }}>
		<main>
			<slot><!-- optional fallback --></slot>
		</main>

		<Footer commitHash={data.commitHash} netlifyID={PUBLIC_NETLIFY_SITE_ID} />
	</div>
{/if}
<SvelteToast options={{ duration: 2000 }} />

<style lang="postcss">
	.content {
		@apply mt-[calc(var(--headerHeight)_+_1rem)] print:mt-0;
	}
	main {
		@apply max-w-5xl m-auto p-4;
	}

	img.favicon {
		@apply inline-block align-text-top h-[1em];
	}
</style>
