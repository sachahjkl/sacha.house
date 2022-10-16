<script lang="ts">
	import { SITE_TITLE } from '$lib/constants';
	import type { PageData } from './$types';

	export let data: PageData;
	const { post } = data;
	const createdAt = new Date(Date.parse(post.createdAt));
	const updatedAt = new Date(Date.parse(post.updatedAt));
</script>

<svelte:head>
	<title>{post.title} / {SITE_TITLE}</title>
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
