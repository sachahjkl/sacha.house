<script lang="ts">
	import Illustration from '$lib/components/Illustration.svelte';
	import TitleArt from '$lib/components/TitleArt.svelte';
	import { MOI } from '$lib/me';

	// export let data;
</script>

<article>
	<h1 class="text-3xl font-bold">Welcome to my website</h1>

	<TitleArt />

	<div class="divider" />
	<h2 class="mt-2 font-bold">Quick links</h2>

	<ul class="ms-8">
		<li><a href="/about">➜ about me</a></li>
		<li><a href="mailto:{MOI.mail}">📧 shoot me an email (will reply asap)</a></li>
	</ul>

	<div class="divider mt-4" />
	<Illustration />
</article>

<style lang="postcss">
	a:hover {
		@apply underline;
	}
</style>
