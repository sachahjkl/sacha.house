<script>
	import Prism from 'prismjs';
	import { onMount } from 'svelte';

    const themeURL = "/prism-okaidia.css"
    // const themeURL = "/prism-vsc-dark-plus.css"

	export let language = '';
	export let code = '';
	let formattedCode = code;

	onMount(async () => {
		formattedCode = Prism.highlight(code, Prism.languages[language], language);
	});
</script>

<svelte:head>
	<link
		rel="stylesheet"
		href={themeURL}
	/>
</svelte:head>

<pre class="language-{language}"><code class="language-{language}">{@html formattedCode}</code
	></pre>

<style lang="postcss">
	pre {
		@apply whitespace-pre-wrap  max-h-[400px] overflow-y-auto shadow;
	}

	pre * {
		@apply break-all whitespace-pre-wrap;
	}
</style>
