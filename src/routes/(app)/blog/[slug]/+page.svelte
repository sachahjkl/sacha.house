<script lang="ts">
	import { MOI } from '$lib/me';
	import type { PageData } from './$types';

	interface Props {
		data: PageData;
	}

	let { data }: Props = $props();
	let post = $state(data.post);
	$effect(() => {
		post = data.post;
	});
	const createdAt = $derived(new Date(Date.parse(post.createdAt)));
	const updatedAt = $derived(new Date(Date.parse(post.updatedAt)));
</script>

<svelte:head>
	<meta property="og:url" content={data.seo.url} />
	<meta property="og:type" content="article" />
	<meta property="og:article:published_time" content={createdAt.toISOString()} />
	{#if updatedAt}
		<meta property="og:article:modified_time" content={updatedAt.toISOString()} />
	{/if}
	<meta property="og:article:author" content="{MOI.prettyPrenom} {MOI.prettyNom}" />
</svelte:head>

<p class="mb-4 text-sm">
	<a href="/blog" class="opacity-60"
		><span class="inline-block rotate-180">➜</span> Go back to the articles list</a
	>
</p>
<h1 class="h1">{post.title}</h1>
<small class="text-textColor/50 text-sm"
	>created on {createdAt.toLocaleDateString()} at {createdAt.toLocaleTimeString()} - last modified on
	{updatedAt.toLocaleDateString()} at {updatedAt.toLocaleTimeString()}</small
>
<article class="prose mt-4">
	{@html post.content.html}
</article>

<style lang="postcss">
	article {
		margin-inline: auto;
	}

	a {
		text-decoration-line: underline;
	}
</style>
