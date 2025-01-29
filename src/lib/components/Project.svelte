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
		class="border-bgColor bg-bgColor text-textColor hover:border-textColor flex overflow-hidden border-4"
	>
		{#if avatarUrl}
			<div class="grid shrink-0 place-content-center">
				<figure>
					<img
						class="aspect-square h-16 w-16 sm:h-32 sm:w-32"
						loading="lazy"
						src={avatarUrl}
						alt="avatar"
					/>
				</figure>
			</div>
		{:else}
			<div
				style={(avatarUrl ?? '').trim() !== ''
					? '--color: lightred'
					: `--color: hsl(${h}, ${s * 100}%, ${l * 100}%)`}
				class="bg-(--color) grid aspect-square h-16 w-16 shrink-0 place-content-center sm:h-32 sm:w-32"
			>
				<span class="flex h-12 w-12 place-content-center place-items-center rounded bg-neutral-900/50 text-3xl text-neutral-100 shadow-smletter text-center">
					{name[0].toUpperCase()}
				</span>
			</div>
		{/if}
		<div class="text-textColor w-full overflow-hidden p-0 text-sm sm:text-base">
			<h2 class="bg-textColor text-bgColor ps-2 font-bold">{name}</h2>
			<div bind:this={descriptionEl} class="line-clamp-2 ps-2 pt-2">
				{@html descriptionHtml ||
					'😞 Unfortunately, no description is available (I was probs lazy ahh).'}
			</div>
		</div>
	</div>
</a>