<script lang="ts">
	import { randomColorHSL } from '$lib/utils';

	export let description = 'N/A';
	export let descriptionHtml = 'N/A';
	export let name = 'Projet';
	export let url = 'https://github.com/torvalds/linux';
	export let avatarUrl = '';
	const [h, s, l] = randomColorHSL();
</script>

<a
	href={url}
	title="{name}
{description}"
>
	<div class="h-32 card card-side bg-base-200 rounded z-10 overflow-hidden">
		{#if avatarUrl}
			<div class="w-32 grid shrink-0 place-content-center">
				<figure>
					<img loading="lazy" class="m-3 drop-shadow" src={avatarUrl} alt="avatar" />
				</figure>
			</div>
		{:else}
			<div
				style={(avatarUrl ?? '').trim() !== ''
					? ''
					: `--color: hsl(${h}, ${s * 100}%, ${l * 100}%)`}
				class="letter-box"
			>
				<span class="letter">
					{name[0].toUpperCase()}
				</span>
			</div>
		{/if}
		<div class="card-body m-3 mr-6 p-0 project-info">
			<h2 class="card-title">{name}</h2>
			<div class="description">
				{@html descriptionHtml || '😞 Pas de description ... '}
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
		@apply shadow m-2 hover:scale-95 active:scale-90 transition-transform;
	}

	.card-body {
		@apply overflow-hidden;
	}
	.letter-box {
		--color: lightred;
		@apply bg-[color:var(--color)] w-32 grid shrink-0 place-content-center;
	}

	.letter {
		@apply w-12 h-12 flex place-items-center place-content-center text-3xl
		rounded bg-neutral-900 text-neutral-100 shadow-sm bg-opacity-50;
	}
</style>
