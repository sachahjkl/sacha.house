<script lang="ts">
	import type { PageData } from '../$types';

	interface Props {
		data: PageData;
	}

	let { data }: Props = $props();
</script>

<article>
	<h1 class="h1">blog</h1>

	<h2 class="font-bold mb-2">📰 Available articles</h2>
	{#await data.streaming.posts}
		<p>Loading ...</p>
	{:then posts}
		<ul data-sveltekit-preload-data class="list-[square] list-inside ms-4">
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
		@apply text-opacity-50 text-sm;
	}
</style>
