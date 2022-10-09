<script lang="ts">
	import ClockDisplay from '$lib/components/ClockDisplay.svelte';
	import { MOI, SITE_TITLE } from '$lib/constants';
	import type { PageData } from './$types';

	export let data: PageData;

	const { participants } = data;
</script>

<svelte:head>
	<title>accueil / {SITE_TITLE}</title>
</svelte:head>
<div class="prose">
	<h1>
		{SITE_TITLE}<span class="visites"><ClockDisplay value={`${participants.value} visites`} /></span
		>
	</h1>
	<hr />
	<h2>Informations de contact / détails</h2>
	<p>
		<a href="/a-propos">à propos de moi</a>
	</p>
	<p>
		<a href="mailto:{MOI.mail}">📧 M'envoyer un mail</a>
	</p>
	<hr />
	<img class="illustration" src="/c-omrade.jpg" alt="comrade" />
</div>

<style lang="postcss">
	div {
		@apply mx-auto;
	}
	hr {
		@apply my-3;
	}
	a {
		@apply text-blue-500 visited:text-purple-500
         hover:text-blue-600 active:text-blue-700;
	}

	.illustration {
		@apply max-w-[80%] m-auto;
	}

	h1 {
		@apply flex justify-between flex-wrap items-center mb-2;
	}

	.visites {
		@apply hover:scale-110 active:scale-125 transition;
	}
</style>
