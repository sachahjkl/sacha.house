<script lang="ts">
	import { randomColor } from '$lib/utils';

	export let description = 'N/A';
	export let name = 'Projet';
	export let url = 'https://github.com/torvalds/linux';
	export let avatarUrl = '';
</script>

<a href={url}>
	<div class="h-32 card card-side bg-base-content text-base-100">
		{#if avatarUrl}
			<div class="w-32 grid shrink-0 place-content-center">
				<figure><img loading="lazy" class="rounded m-3" src={avatarUrl} alt="avatar" /></figure>
			</div>
		{:else}
			<div
				style={(avatarUrl ?? '').trim() !== '' ? '' : `--color: ${randomColor()}`}
				class="letter w-32 grid shrink-0 place-content-center text-3xl"
			>
				<span class="py-2 px-4 rounded bg-base-100 text-base-content shadow-sm bg-opacity-50">
					{name[0].toUpperCase()}
				</span>
			</div>
		{/if}
		<div class="card-body p-4 project-info">
			<h2 class="card-title">{name}</h2>
			{@html description || '😞 Pas de description ... '}
		</div>
	</div>
</a>

<style lang="postcss">
	:global(.card a) {
		@apply link focus:scale-105;
	}
	:global(.project-info p) {
		@apply overflow-hidden text-ellipsis;
	}
	div.card {
		@apply shadow m-2 hover:scale-95 active:scale-[1.01] transition-transform;
	}
	.letter {
		--color: lightred;
		@apply bg-[color:var(--color)];
	}
</style>
