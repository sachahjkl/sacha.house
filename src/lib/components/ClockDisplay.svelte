<script lang="ts">
	export let value = '';
	export let clickCallback = () => {};

	let text: HTMLSpanElement;
	let characters: number = 20;
	$: characters = value.length;
</script>

<time on:click={clickCallback} on:keypress={clickCallback}>
	<span class="text" bind:this={text}>
		<span class="char-grid">
			{Array.from(Array(characters - 1))
				.map(() => '8')
				.join('')}
		</span>
		{value}
	</span>
</time>

<style lang="postcss">
	time {
		@apply border-2 rounded-sm border-zinc-900  px-2 py-1
         text-2xl shadow text-center block drop-shadow-md my-auto
		 cursor-pointer text-red-600 italic flex-grow-0 h-min select-none;
		background-color: rgb(31, 0, 0);
	}

	.text {
		--color: rgb(230, 67, 67);
		text-shadow: 0 0 5px var(--color);
		@apply inline-block w-auto mx-auto relative rounded;
		font-family: 'Digital-7', 'monospace';
		transition-property: text-shadow, color;
		transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
		transition-duration: 150ms;
	}

	.char-grid {
		@apply opacity-25 absolute left-0;
	}

	time:hover .text {
		@apply text-red-500;
		text-shadow: 0 0 10px var(--color);
	}
</style>
