<script lang="ts">
	import { page } from '$app/stores';
	import { themeChange } from 'theme-change';
	import '$lib/app.css';
	import { onMount } from 'svelte';
	import { MOI } from '$lib/constants';
	import { capitalize } from '$lib/utils';
	import { PUBLIC_NETLIFY_SITE_ID, PUBLIC_USE_INTRO } from '$env/static/public';
	import HamburgerIcon from '$lib/components/HamburgerIcon.svelte';
	import { fly } from 'svelte/transition';

	const navItems = [
		{ icon: '🏡', title: 'accueil', slug: '/' },
		{ icon: '📁', title: 'projets', slug: '/projets' },
		{ icon: '📜', title: 'à propos', slug: '/a-propos' }
	];

	const useIntro: boolean = JSON.parse(PUBLIC_USE_INTRO);
	let init = useIntro ? false : true;

	onMount(() => (init = true));

	onMount(() => {
		themeChange(false);
	});
</script>

<nav>
	<ul class="inline-list">
		<li class="title md:order-first ">
			<img class="favicon" src="/favicon_shadow.png" alt="favicon" />
			{MOI.prenom.substring(1)}
			{capitalize(MOI.nom)}
		</li>
		<li class="dropdown md:hidden order-first ">
			<label tabindex="0" for="navDropdown" class="btn border gap-2 btn-primary m-1">
				<HamburgerIcon />
				Menu
			</label>
			<ul
				id="navDropdown"
				tabindex="0"
				class="dropdown-content border menu shadow bg-base-100 rounded-box w-52"
			>
				{#each navItems as item}
					<li>
						<a class:active={$page.url.pathname === item.slug} href={item.slug}>
							{item.icon}
							{item.title}
						</a>
					</li>
				{/each}
				<li class="select-none flex items-center">
					<form class=" w-full">
						🌚 <input
							type="checkbox"
							data-toggle-theme="light,dark"
							data-act-class="ACTIVECLASS"
							class="toggle toggle-sm"
						/> 🌞
					</form>
				</li>
			</ul>
		</li>
		{#each navItems as item}
			<li class="item-inline">
				<a class:active={$page.url.pathname === item.slug} href={item.slug}>
					{item.icon}
					{item.title}
				</a>
			</li>
		{/each}

		<li class="hidden md:flex items-center select-none">
			🌚 <input
				type="checkbox"
				data-toggle-theme="light,dark"
				data-act-class="ACTIVECLASS"
				class="toggle toggle-sm mx-2"
			/> 🌞
		</li>
	</ul>
</nav>

{#if init}
	<div class="content" in:fly={{ y: -50 }}>
		<main>
			<slot><!-- optional fallback --></slot>
		</main>

		<footer class="footer justify-between p-4 max-w-5xl m-auto mt-3">
			<div class="items-center grid-flow-col">
				<img class="favicon" src="/favicon_shadow.png" alt="Logo" />
				<p>Copyright © 2022 - All right reserved</p>
			</div>
			<img
				src="https://api.netlify.com/api/v1/badges/{PUBLIC_NETLIFY_SITE_ID}/deploy-status"
				alt="Deploy Status Badge"
			/>
		</footer>
	</div>
{/if}

<style lang="postcss">
	main {
		@apply max-w-5xl m-auto mt-4 p-4;
	}
	.active {
		@apply font-bold;
	}

	img.favicon {
		@apply inline-block align-text-top h-[1em];
	}

	nav {
		@apply m-2 flex flex-wrap justify-between;
	}

	ul.inline-list {
		@apply flex flex-wrap content-center md:justify-start justify-between w-full;
	}

	.item-inline {
		@apply mx-2 my-auto md:block hidden;
	}
	.item-inline a {
		@apply hover:underline inline-block text-blue-500 hover:-translate-y-1
		py-2 active:-translate-y-2 transition;
	}

	.title {
		@apply font-bold mx-2 my-auto inline-block;
	}
</style>
