<script>
	import '$lib/app.css';
	/** @type {{children?: import('svelte').Snippet}} */
	let { children } = $props();
</script>

<main>
	{@render children?.()}
</main>

<style lang="postcss">
	main {
		@apply m-auto mt-6 max-w-5xl p-4;
	}
</style>
