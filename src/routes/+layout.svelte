<script lang="ts">
	import { page } from '$app/stores';
	import { themeChange } from 'theme-change';
	import '$lib/app.css';
	import { onMount } from 'svelte';
	onMount(() => {
		themeChange(false);
	});
</script>

<nav>
	<ul>
		<li class="title">
			<img src="/favicon_shadow.png" alt="favicon" />
			acha Froment
		</li>
		<li>
			<a class:active={$page.url.pathname.match(/^\/$/g)} href="/"> 🏡 accueil </a>
		</li>

		<li>
			<a class:active={$page.url.pathname.match(/^\/projets/g)} href="/projets"> 📁 projets </a>
		</li>

		<li>
			<a class:active={$page.url.pathname.match(/^\/a-propos/g)} href="/a-propos"> 📜 à propos </a>
		</li>
		<li class="flex items-center">
			🌚 <input
				type="checkbox"
				data-toggle-theme="light,business"
				data-act-class="ACTIVECLASS"
				class="toggle toggle-sm mx-2"
			/> 🌞
		</li>
	</ul>
</nav>

<main>
	<slot><!-- optional fallback --></slot>
</main>

<style lang="postcss">
	main {
		@apply max-w-5xl m-auto p-4;
	}

	.active {
		@apply font-bold;
	}

	.title {
	}

	img {
		@apply inline-block align-text-top h-[1em];
	}

	nav {
		@apply m-2;
	}

	ul {
		@apply flex flex-wrap content-center;
	}

	li {
		@apply mx-2 my-auto;
	}
	a {
		@apply hover:underline inline-block text-blue-500 hover:-translate-y-1
		py-2 active:-translate-y-2 transition;
	}

	.title {
		@apply font-bold;
	}
</style>
