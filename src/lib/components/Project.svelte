<script lang="ts">
	import { debounce, randomColorHSL } from '$lib/utils';
	import { onMount } from 'svelte';

	interface Props {
		description?: string;
		descriptionHtml?: string;
		name?: string;
		url?: string;
		avatarUrl?: string;
	}

	let {
		description = 'N/A',
		descriptionHtml = 'N/A',
		name = 'Projet',
		url = 'https://github.com/torvalds/linux',
		avatarUrl = ''
	}: Props = $props();
	const [h, s, l] = randomColorHSL();

	let descriptionEl: HTMLElement = $state() as HTMLElement;

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
	<div
		class="card card-side flex h-32 overflow-hidden border-4 border-bgColor bg-bgColor text-textColor hover:border-textColor"
	>
		{#if avatarUrl}
			<div class="grid w-32 shrink-0 place-content-center">
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
		<div class="w-full overflow-hidden p-0 text-textColor">
			<h2 class="bg-textColor ps-2 font-bold text-bgColor">{name}</h2>
			<div bind:this={descriptionEl} class="description ps-2">
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
		@apply grid w-32 shrink-0 place-content-center bg-[color:var(--color)];
	}

	.letter {
		@apply flex h-12 w-12 place-content-center place-items-center rounded bg-neutral-900 bg-opacity-50 text-3xl text-neutral-100 shadow-sm;
	}
</style>
