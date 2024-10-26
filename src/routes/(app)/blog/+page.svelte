<script lang="ts">
	import type { PageData } from './$types';

	interface Props {
		data: PageData;
	}

	let { data }: Props = $props();
</script>

<article>
	<h1 class="h1">blog</h1>

	<h2 class="mb-2 font-bold">📰 Available articles</h2>
	{#await data.posts}
		<p>Loading ...</p>
	{:then posts}
		<ul data-sveltekit-preload-data class="ms-4 list-inside list-[square]">
			{#each posts as post}
				<li>
					<a href="/blog/{post.slug}">{post.title}</a>
					-
					<span class="time">
						on
						<time>{new Date(post.updatedAt).toLocaleDateString()} </time> at
						<time>{new Date(post.updatedAt).toLocaleTimeString()}</time>
					</span>
				</li>
			{:else}
				<li>No posts available</li>
			{/each}
		</ul>
	{/await}
</article>

<style lang="postcss">
	article {
		@apply mx-auto;
	}

	a {
		@apply hover:underline;
	}

	.time {
		@apply text-sm text-opacity-50;
	}
</style>
