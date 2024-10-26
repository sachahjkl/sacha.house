<script lang="ts">
	import { PRETTY_NOM, PRETTY_PRENOM } from '$lib/me';

	export let data;
	let post: typeof data.post = data.post;
	$: post = data.post;
	const createdAt = new Date(Date.parse(post.createdAt));
	const updatedAt = new Date(Date.parse(post.updatedAt));
</script>

<svelte:head>
	<meta property="og:url" content={data.seo.url} />
	<meta property="og:type" content="article" />
	<meta property="og:article:published_time" content={createdAt.toISOString()} />
	{#if updatedAt}
		<meta property="og:article:modified_time" content={updatedAt.toISOString()} />
	{/if}
	<meta property="og:article:author" content="{PRETTY_PRENOM} {PRETTY_NOM}" />
</svelte:head>

<p>
	<a href="/blog" class="opacity-60"
		><span class="rotate-180 inline-block">➜</span> Go back to the articles list</a
	>
</p>
<h1 class="h1">{post.title}</h1>
<small class="text-textColor text-opacity-50 text-sm"
	>created on {createdAt.toLocaleDateString()} at {createdAt.toLocaleTimeString()} - last modified on
	{updatedAt.toLocaleDateString()} at {updatedAt.toLocaleTimeString()}</small
>
<article class="prose mt-4">
	{@html post.content.html}
</article>

<style lang="postcss">
	article {
		@apply mx-auto;
	}

	a {
		@apply underline;
	}
</style>
