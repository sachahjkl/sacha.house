<script lang="typescript">
	import { highlighter } from '$lib/utils';

	/** @type {{language?: string, code?: string}} */
	let { language = '', code = '' } = $props();
	let formattedCode = $state(highlighter.codeToHtml(code, { lang: language, theme: 'monokai' }));

	$effect(() => {
		formattedCode = highlighter.codeToHtml(code, { lang: language, theme: 'monokai' });
	});
</script>

{@html formattedCode}
