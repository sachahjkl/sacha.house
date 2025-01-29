<script lang="ts">
	interface Props {
		value?: string;
		clickCallback?: () => void;
	}

	let { value = '', clickCallback = () => undefined }: Props = $props();

	// let text: HTMLSpanElement;
	let characters = $state(20);
	$effect(() => {
		characters = value.length;
	});
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<time
	class="my-auto block h-min grow-0 cursor-pointer rounded-sm border-2 border-zinc-900 px-2 py-1 text-center text-2xl text-red-600 italic shadow drop-shadow-md select-none"
	onclick={clickCallback}
	onkeypress={clickCallback}
>
	<span class="text relative mx-auto inline-block w-auto rounded text-red-500">
		<span class="absolute left-0 opacity-25">
			{Array.from(Array(characters - 1))
				.map(() => '8')
				.join('')}
		</span>
		{value}
	</span>
</time>

<style lang="postcss">
	time {
		background-color: rgb(31, 0, 0);
	}

	.text {
		--color: rgb(230, 67, 67);
		text-shadow: 0 0 5px var(--color);
		font-family: 'Digital-7', 'monospace';
		transition-property: text-shadow, color;
		transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
		transition-duration: 150ms;
	}

	time:hover .text {
		text-shadow: 0 0 10px var(--color);
	}
</style>
