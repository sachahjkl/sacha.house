<script lang="ts">
	import Illustration from '$lib/components/Illustration.svelte';
	import TitleArt from '$lib/components/TitleArt.svelte';
	import { MOI } from '$lib/me';

	// export let data;
</script>

<article class="prose">

	
	<TitleArt/>

	<h1>Welcome to my website</h1>

	<div class="divider" />
	<h2 class="mt-2">Informations de contact / détails</h2>
	<p data-sveltekit-preload-data>
		➜ <a href="/a-propos">à propos de moi</a>
	</p>
	<p>
		📧 <a href="mailto:{MOI.mail}">M'envoyer un mail</a>
	</p>
	<!-- <div class="visites md:hidden inline-block">
		<ClockDisplay value={`${data.visites} visites`} />
	</div> -->
	<div class="divider" />
	<Illustration />
</article>

<style lang="postcss">
</style>
