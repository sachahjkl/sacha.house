<script lang="ts">
	import { toId } from '$lib/utils';
	import { copy } from 'svelte-copy';

	interface Props {
		value?: string;
		iconEl?: HTMLElement;
	}

	let { value = '', iconEl = $bindable() }: Props = $props();
	const id = toId(value);
	let timeout: number;
</script>

<button
	class="break-all text-start underline"
	use:copy={{
		text: value,
		onCopy({ text }) {
			if(timeout) clearTimeout(timeout);
			console.log('Copied! ' + text);
			iconEl?.classList.add('copied');
			timeout = setTimeout(() => {
				iconEl?.classList.remove('copied');
			}, 1000);
		},

	}}
	id="copy-{id}">{value}</button
>
<span bind:this={iconEl} class="copy-icon inline-block">📋</span>

<style lang="postcss">
	/* run a spin animation on the copy icon when the "copied" class is added but only forwards and once */
	:global(.copy-icon.copied) {
		/* add ease-in-out to the spin animation */
		animation: icon-spin 0.5s ease-out forwards;
	}
	@keyframes icon-spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
