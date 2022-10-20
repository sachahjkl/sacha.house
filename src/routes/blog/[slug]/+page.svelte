<script lang="ts">
	import { PRETTY_NOM, PRETTY_PRENOM } from '$lib/me';
	import type { PageData } from './$types';

	export let data: PageData;
	const { post } = data;
	const createdAt = new Date(Date.parse(post.createdAt));
	const updatedAt = new Date(Date.parse(post.updatedAt));
</script>

<svelte:head>
	<meta property="og:url" content={data.seo.url} />
	<meta property="og:type" content="article" />
	<meta property="og:article:published_time" content={createdAt.toISOString()} />
	{updatedAt
		? `<meta property="og:article:modified_time" content="${updatedAt.toISOString()}"/>`
		: ''}
	<meta property="og:article:author" content="{PRETTY_PRENOM} {PRETTY_NOM}" />
</svelte:head>

<article class="prose">
	<p>
		<a href="/blog" class="text-base-content opacity-60"
			><span class="rotate-180 inline-block">➜</span> Retour à la liste des articles</a
		>
	</p>
	<h1>{post.title}</h1>
	<small
		>créé le {createdAt.toLocaleDateString()} à {createdAt.toLocaleTimeString()} - dernière modification
		le {updatedAt.toLocaleDateString()} à {updatedAt.toLocaleTimeString()}</small
	>
	{@html post.content.html}
</article>

<style lang="postcss">
	article {
		@apply mx-auto;
	}
</style>
