<script lang="ts">
	import { randomColor } from '$lib/utils';

	export let description = 'N/A';
	export let name = 'Projet';
	export let url = 'https://github.com/torvalds/linux';
	export let avatarUrl = '';
</script>

<a href={url}>
	<div class="card card-side">
		<div
			style={(avatarUrl ?? '').trim() !== '' ? '' : `--color: ${randomColor()}`}
			class="[]bg-base-300 letter w-32 grid shrink-0 content-center justify-center text-3xl text-base-content"
		>
			{#if avatarUrl}
				<figure><img loading="lazy" class="m-2 rounded" src={avatarUrl} alt="avatar" /></figure>
			{:else}
				<span class="py-2 px-4 rounded bg-base-100 shadow-sm bg-opacity-50">
					{name[0].toUpperCase()}
				</span>
			{/if}
		</div>
		<div class="card-body p-4">
			<h2 class="card-title">{name}</h2>
			{@html description || '😞 Pas de description ... '}
		</div>
	</div>
</a>

<style lang="postcss">
	:global(.card a) {
		@apply link hover:text-primary focus:text-primary-focus ;
	}
	div.card {
		@apply bg-base-100 border shadow m-2 hover:scale-95 active:scale-105 transition-transform;
	}
	.letter {
		--color: lightred;
		@apply bg-[color:var(--color)];
	}
</style>
