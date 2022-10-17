<script lang="ts">
	import type { PageData } from './$types';

	export let data: PageData;

	const { posts } = data;
</script>

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
