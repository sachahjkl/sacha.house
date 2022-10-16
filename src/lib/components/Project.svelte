<script lang="ts">
	import { randomColorHSL } from '$lib/utils';

	export let description = 'N/A';
	export let name = 'Projet';
	export let url = 'https://github.com/torvalds/linux';
	export let avatarUrl = '';
	const [h, s, l] = randomColorHSL();
</script>

<a href={url}>
	<div class="h-32 card card-side bg-base-200">
		{#if avatarUrl}
			<div class="w-32 grid shrink-0 place-content-center">
				<figure>
					<img loading="lazy" class="rounded m-3 drop-shadow" src={avatarUrl} alt="avatar" />
				</figure>
			</div>
		{:else}
			<div
				style={(avatarUrl ?? '').trim() !== '' ? '' : `--color: hsl(${h}, ${s}%, ${l}%)`}
				class="letter-box"
			>
				<span class="letter">
					{name[0].toUpperCase()}
				</span>
			</div>
		{/if}
		<div class="card-body p-4 project-info">
			<h2 class="card-title">{name}</h2>
			<div class="description">
				{@html description || '😞 Pas de description ... '}
			</div>
		</div>
	</div>
</a>

<style lang="postcss">
	:global(.card a) {
		@apply link focus:scale-105;
	}
	.description {
		@apply line-clamp-2;
	}
	div.card {
		@apply shadow m-2 hover:scale-95 active:scale-[1.01] transition-transform;
	}
	.letter-box {
		--color: lightred;
		@apply bg-[color:var(--color)] w-32 grid shrink-0 place-content-center shadow border-r-2 border-r-base-300;
	}

	.letter {
		@apply w-12 h-12 flex place-items-center place-content-center text-3xl
		rounded bg-base-100 text-base-content shadow-sm bg-opacity-50;
	}
</style>
