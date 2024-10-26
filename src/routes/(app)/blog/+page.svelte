<script lang="ts">
	export let data;
</script>

<article class="prose">
	<h1>blog</h1>

	<h2>📰 Liste des articles</h2>
	{#await data.streaming.posts}
		<p>Loading ...</p>
	{:then posts}
		<ul data-sveltekit-preload-data>
			{#each posts as post}
				<li>
					<a href="/blog/{post.slug}">{post.title}</a>
					-
					<span class="time">
						le
						<time>{new Date(post.updatedAt).toLocaleDateString()} </time> à
						<time>{new Date(post.updatedAt).toLocaleTimeString()}</time>
					</span>
				</li>
			{:else}
				<li>Pas de poste</li>
			{/each}
		</ul>
	{/await}
</article>

<style lang="postcss">
	article {
		@apply mx-auto;
	}

	.time {
		@apply  text-opacity-50 text-sm;
	}
</style>
