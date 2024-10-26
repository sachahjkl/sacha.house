<script lang="ts">
	import { toId } from '$lib/utils';
	import { copy } from 'svelte-copy';

	interface Props {
		value?: string;
	}

	let { value = '' }: Props = $props();
	const id = toId(value);
</script>

<a use:copy={value} id="copy-{id}" href="#copy-{id}" class="break-words">{value} </a>
<span class="copy-icon">📋</span>
