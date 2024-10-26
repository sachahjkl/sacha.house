<script lang="ts">
	import { page } from '$app/stores';
	import { statusCodeToText } from '$lib/utils';
</script>

<main>
	<h1>{$page.status} {statusCodeToText($page.status)}</h1>
	<p>{@html $page.error?.message.replaceAll('\n', '</br>')}</p>
</main>

<style lang="postcss">
	main {
		@apply m-auto mt-6 max-w-5xl p-4;
	}
</style>
