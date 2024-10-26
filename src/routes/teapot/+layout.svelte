<script>
	import '$lib/app.css';
	/** @type {{children?: import('svelte').Snippet}} */
	let { children } = $props();
</script>

<main >
	{@render children?.()}
</main>

<style lang="postcss">
	main {
		@apply max-w-5xl m-auto mt-6 p-4;
	}
</style>
