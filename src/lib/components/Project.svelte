<script lang="ts">
	import { debounce, randomColorHSL } from '$lib/utils';
	import { onMount } from 'svelte';

	export let description = 'N/A';
	export let descriptionHtml = 'N/A';
	export let name = 'Projet';
	export let url = 'https://github.com/torvalds/linux';
	export let avatarUrl = '';
	const [h, s, l] = randomColorHSL();

	let descriptionEl: HTMLElement;

	onMount(() => {
		const onResize = debounce(() => {
			const csslineHeight = getComputedStyle(descriptionEl).lineHeight;
			const possibleLines = Math.floor(descriptionEl.clientHeight / parseFloat(csslineHeight));
			descriptionEl.style.webkitLineClamp = `${possibleLines}`;
		}, 200);
		window.addEventListener('resize', onResize);
		onResize();
		return () => window.removeEventListener('resize', onResize);
	});
</script>

<a
	href={url}
	title="{name}
{description}"
>
	<div class="h-32 card card-side flex gap-4 overflow-hidden bg-bgColor text-textColor border-2 hover:border-textColor border-bgColor">
		{#if avatarUrl}
			<div class="w-32 grid shrink-0 place-content-center p-4">
				<figure>
					<img loading="lazy" src={avatarUrl} alt="avatar" />
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
		<div class="overflow-hidden w-full text-textColor m-3 mr-6 p-0">
			<h2 class="ps-2 font-bold bg-textColor text-bgColor">{name}</h2>
			<div bind:this={descriptionEl} class="description">
				{@html descriptionHtml || '😞 Pas de description ... '}
			</div>
		</div>
	</div>
</a>

<style lang="postcss">
	.description {
		@apply line-clamp-2;
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
