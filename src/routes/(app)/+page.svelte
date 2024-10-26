<script lang="ts">
	import Illustration from '$lib/components/Illustration.svelte';
	import TitleArt from '$lib/components/TitleArt.svelte';
	import { MOI } from '$lib/me';

	// export let data;
</script>

<article>
	<h1 class="h1">welcome to my website</h1>

	<TitleArt />

	<div class="divider"></div>
	<h2 class="h2">Quick links</h2>

	<ul class="ms-8">
		<li><a href="/about">➜ about me</a></li>
		<li><a href="mailto:{MOI.mail}">📧 shoot me an email (will reply asap)</a></li>
		<li><a href="/teapot">🍵 teapot</a></li>
	</ul>

	<div class="divider mt-4"></div>
	<Illustration />
</article>

<style lang="postcss">
	a:hover {
		@apply underline;
	}
</style>
