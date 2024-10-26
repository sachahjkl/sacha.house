<script lang="ts">
	import type { PageData } from './$types';

	interface Props {
		data: PageData;
	}

	let { data }: Props = $props();
</script>

<p>
	<a href="/" class=" opacity-60"> <span class="inline-block rotate-180">➜</span> Home</a>
</p>
<h1 class="h1">Here, let's make you a nice cup of :</h1>

<ul>
	<li><a href="?drink=tea">Tea</a></li>
	<li><a href="?drink=coffee">Coffee</a></li>
	<li><a href="?drink={data.spewage}">Random spewage</a></li>
</ul>
{#if data.brewMessage}
	<hr class="my-4 border-2" />
	<p class="text-center text-4xl font-black">
		{data.brewMessage.text}
	</p>
	<p class="mt-20 animate-bounce text-center text-9xl drop-shadow-md">
		{data.brewMessage.emoji}
	</p>
{/if}

<style lang="postcss">
	a:hover {
		@apply underline;
	}
</style>
