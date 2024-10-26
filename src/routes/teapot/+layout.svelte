<script>
	import '$lib/app.css';
</script>

<main >
	<slot />
</main>

<style lang="postcss">
	main {
		@apply max-w-5xl m-auto mt-6 p-4;
	}
</style>
