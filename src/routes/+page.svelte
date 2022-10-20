<script lang="ts">
	import ClockDisplay from '$lib/components/ClockDisplay.svelte';
	import { MOI, SITE_TITLE } from '$lib/me';

	import comrade from '$lib/assets/c-omrade.jpg';

	import type { PageData } from './$types';

	export let data: PageData;
</script>

<article class="prose">
	<h1>
		{SITE_TITLE}
		<div class="visites hidden md:inline-block">
			<ClockDisplay value={`${data.visites} visites`} />
		</div>
	</h1>
	<div class="divider" />
	<h2 class="mt-2">Informations de contact / détails</h2>
	<p data-sveltekit-prefetch>
		➜ <a href="/a-propos">à propos de moi</a>
	</p>
	<p>
		📧 <a href="mailto:{MOI.mail}">M'envoyer un mail</a>
	</p>
	<div class="visites md:hidden inline-block">
		<ClockDisplay value={`${data.visites} visites`} />
	</div>
	<div class="divider" />
	<img class="illustration" src={comrade} alt="comrade" />
</article>

<style lang="postcss">
	.prose {
		@apply mx-auto;
	}
	a {
		@apply text-blue-500 visited:text-purple-500
         hover:text-blue-600 active:text-blue-700;
	}

	.illustration {
		@apply max-w-[60%] m-auto hover:scale-95
		active:scale-90 transition-all;
	}

	h1 {
		@apply flex justify-between flex-wrap content-center items-center mb-2;
	}

	.visites {
		@apply hover:scale-110 active:scale-125 transition;
	}
</style>
