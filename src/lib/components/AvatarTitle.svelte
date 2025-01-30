<script lang="ts">
	import { fade, fly } from 'svelte/transition';

	interface Props {
		imgSrc?: string;
		children?: import('svelte').Snippet;
	}

	let { imgSrc = '/me.jpg', children }: Props = $props();
</script>

<div in:fade class="flex items-center">
	<div in:fly={{ x: -50 }} class="mx-2 transition-transform hover:scale-95 active:scale-105">
		<div class="ring-primary w-[2em] rounded-full ring-3 ring-offset-2">
			<img class="m-0" src={imgSrc} alt="title" />
		</div>
	</div>
	<span in:fly={{ x: 50 }} class="ml-3"
		>{#if children}{@render children()}{:else}My Title{/if}</span
	>
</div>

<style lang="postcss">
</style>
