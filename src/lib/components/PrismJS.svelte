<script>
	import Prism from 'prismjs';
	import { onMount } from 'svelte';

	const themeURL = '/prism-okaidia.css';
	// const themeURL = "/prism-vsc-dark-plus.css"

	/** @type {{language?: string, code?: string}} */
	let { language = '', code = '' } = $props();
	let formattedCode = $state(code);

	$effect(() => {
		formattedCode = Prism.highlight(code, Prism.languages[language], language);
	});

	onMount(async () => {
		formattedCode = Prism.highlight(code, Prism.languages[language], language);
	});
</script>

<svelte:head>
	<link rel="stylesheet" href={themeURL} />
</svelte:head>

<pre class="language-{language} max-h-[400px] overflow-y-auto whitespace-pre-wrap shadow"><code
		class="language-{language}">{@html formattedCode}</code
	></pre>

<style lang="postcss">
	pre * {
		white-space: pre-wrap;
		word-break: break-all;
	}
</style>
