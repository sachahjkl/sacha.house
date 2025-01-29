<script lang="ts">
	import Illustration from '$lib/components/Illustration.svelte';
	import TitleArt from '$lib/components/TitleArt.svelte';
	import { MOI } from '$lib/me';
</script>

<article>
	<h1 class="h1">welcome to my website</h1>
	<section class="mb-8">
		<TitleArt />
	</section>

	<section class="mb-8">
		<h2 class="h2">Quick links</h2>

		<ul class="">
			<li><a href="/about">➜ about me</a></li>
			<li><a href="mailto:{MOI.mail}">📧 shoot me an email (will reply asap)</a></li>
			<li><a href="/sachahjkl.gpg">🔐 my gpg key: 21D64EBC463D12DFE373AE4F1EFE264F809A2118</a></li>
			<li><a href="/teapot">🍵 teapot</a></li>
		</ul>
	</section>

	<section class="mb-8">
		<Illustration />
	</section>
</article>

<style lang="postcss">
	a:hover {
		@apply underline;
	}
</style>
