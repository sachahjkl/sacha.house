<script lang="ts">
	import { toast } from '@zerodevx/svelte-toast';
	import { copy } from 'svelte-copy';

	const toastMessage = (content: string) => `
	<strong>📋 Copié dans le presse papier</strong><br>
	Vous avez copié "${content}"`;

	export let value = '';
</script>

<pre
	class="inline m-0 p-1"
	use:copy={value}
	on:svelte-copy={(event) => toast.push(toastMessage(event.detail))}><code class="hover:underline"
		>{value} 📋</code
	></pre>


<style lang="postcss">
	pre {
		@apply whitespace-pre-wrap break-all;
	}
	code {
		@apply transition-all;
	}
</style>
