<script lang="ts">
	import { toast } from '@zerodevx/svelte-toast';
	import { copy } from 'svelte-copy';

	const toastMessage = (content: string) => `
	<strong>📋 Copié dans le presse papier</strong><br>
	Vous avez copié "${content}"`;

	export let value = '';
</script>

<code use:copy={value} on:svelte-copy={(event) => toast.push(toastMessage(event.detail))}>
	<span class="value">{value}</span> <span class="copy-icon">📋</span>
</code>

<style lang="postcss">
	code {
		@apply inline-flex transition-all px-2 py-1 rounded m-1 hover:ring active:scale-105;
	}
	.value {
		@apply inline-block  max-w-[30ch] overflow-x-scroll hover:underline;
		-ms-overflow-style: none; /* for Internet Explorer, Edge */
		scrollbar-width: none;
	}

	.value::-webkit-scrollbar {
		@apply hidden;
	}

	.copy-icon {
		@apply active:scale-125 transition-all;
	}

	@keyframes bounce {
		0%,
		100% {
			transform: none;
			animation-timing-function: cubic-bezier(0, 0, 0.2, 1);
		}
		50% {
			transform: translateY(-25%);
			animation-timing-function: cubic-bezier(0.8, 0, 1, 1);
		}
	}
	code:hover .copy-icon {
		animation: bounce 1s infinite;
	}
</style>
