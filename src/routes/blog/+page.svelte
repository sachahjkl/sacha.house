<script lang="ts">
	import { SITE_TITLE } from '$lib/constants';
	import type { PageData } from './$types';

	export let data: PageData;

	const { posts } = data;
	const TITLE = `blog / ${SITE_TITLE}`;
	const DESCRIPTION =
		"Mon blog dans lequel je posterai (rarement) des sujets, portant souvent sur l'informatique.";
</script>

<svelte:head>
	<title>{TITLE}</title>
	<meta name="og:title" content={TITLE} />
	<meta name="twitter:title" content={TITLE} />
	<meta name="og:description" content={DESCRIPTION} />
	<meta name="twitter:description" content={DESCRIPTION} />
	<meta name="description" content={DESCRIPTION} />
</svelte:head>

<article class="prose">
	<h1>blog</h1>

	<h2>Liste des articles</h2>
	<ul>
		{#each posts as post}
			<li><a href="/blog/{post.slug}">{post.title}</a></li>
		{:else}
			<li>Pas de poste</li>
		{/each}
	</ul>
</article>

<style lang="postcss">
	article {
		@apply mx-auto;
	}
</style>
