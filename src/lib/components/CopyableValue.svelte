<script lang="ts">
	import { toId } from '$lib/utils';
	import { copy } from 'svelte-copy';

	const toastMessage = (content: string) => `pasted "${content}"`;

	export let value = '';
	const id = toId(value);
</script>

<!-- use:copy={value} on:svelte-copy={(event) => alert(toastMessage(event.detail))}> -->
<a use:copy={value} id="copy-{id}" href="#copy-{id}" class="break-words">{value} </a>
<span class="copy-icon">📋</span>
