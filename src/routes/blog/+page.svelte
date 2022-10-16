<script lang="ts">
	import { SITE_TITLE } from '$lib/constants';
</script>

<svelte:head>
	<title>admin / {SITE_TITLE}</title>
</svelte:head>

<article class="prose">
	<h1>blog</h1>

	<section>
		<h2>Dernier article - {new Date().toLocaleDateString()} à {new Date().toLocaleTimeString()}</h2>

		<p>
			Lorem ipsum, dolor sit amet consectetur adipisicing elit. Fugit sequi quisquam quos similique
			adipisci, temporibus animi incidunt nihil mollitia ipsum? Autem quae porro nihil praesentium
			necessitatibus mollitia ducimus, quisquam impedit.
		</p>
	</section>
</article>

<style lang="postcss">
	article {
		@apply mx-auto;
	}
</style>
