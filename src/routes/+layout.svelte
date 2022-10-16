<script lang="ts">
	import '$lib/app.css';
	import { page } from '$app/stores';
	import { onMount } from 'svelte';
	import { fly } from 'svelte/transition';
	import { themeChange } from 'theme-change';
	import { MOI } from '$lib/constants';
	import { capitalize } from '$lib/utils';
	import { PUBLIC_NETLIFY_SITE_ID, PUBLIC_USE_INTRO } from '$env/static/public';
	import HamburgerIcon from '$lib/components/HamburgerIcon.svelte';
	import { SvelteToast } from '@zerodevx/svelte-toast';
	import type { LayoutData } from './$types';

	export let data: LayoutData;
	const { navItems } = data;

	const year = new Date().getFullYear();

	const useIntro: boolean = JSON.parse(PUBLIC_USE_INTRO);
	let init = useIntro ? false : true;

	onMount(() => (init = true));

	onMount(() => {
		themeChange(false);
	});
	let headerheight = 0; // in pixels;
</script>

<header bind:clientHeight={headerheight}>
	<nav>
		<ul class="inline-list">
			<li class="title md:order-first ">
				<a href="/">
					<img class="favicon" src="/favicon_shadow.png" alt="favicon" />
					{MOI.prenom.substring(1)}
					{capitalize(MOI.nom)}
				</a>
			</li>
			<li class="dropdown md:hidden order-first ">
				<!-- svelte-ignore a11y-no-noninteractive-tabindex -->
				<!--
					INFO :  We use a <label tabindex="0"> instead of a <button>
					because Safari has a bug that prevents the button from being focused.
				-->
				<label tabindex="0" for="navDropdown" class="btn border gap-2 btn-primary m-1">
					<HamburgerIcon />
					Menu
				</label>
				<!-- svelte-ignore a11y-no-noninteractive-tabindex -->
				<!--
					 Using tabindex="0" is required so the dropdown can be focused.
				-->
				<ul
					id="navDropdown"
					tabindex="0"
					class="dropdown-content border menu shadow bg-base-100 rounded-box w-52"
				>
					{#each navItems as item}
						<li>
							<a class:active={$page.url.pathname === item.pathname} href={item.pathname}>
								{item.icon}
								{item.title}
							</a>
						</li>
					{/each}
					<li class="select-none flex items-center hover-bounce">
						<form class=" w-full">
							<span class="bounce">🌚</span>
							<input
								type="checkbox"
								data-toggle-theme="light,dark"
								data-act-class="ACTIVECLASS"
								class="toggle toggle-sm"
							/> <span class="bounce">🌞</span>
						</form>
					</li>
				</ul>
			</li>
			{#each navItems as item}
				<li class="item-inline">
					<a class:active={$page.url.pathname === item.pathname} href={item.pathname}>
						{item.icon}
						{item.title}
					</a>
				</li>
			{/each}

			<li class="hidden md:flex items-center select-none hover-bounce">
				<span class="bounce">🌚</span>
				<input
					type="checkbox"
					data-toggle-theme="light,dark"
					data-act-class="ACTIVECLASS"
					class="toggle toggle-sm mx-2"
				/> <span class="bounce">🌞</span>
			</li>
		</ul>
	</nav>
</header>

{#if init}
	<div style="--headerHeight: {headerheight}px" class="content" in:fly={{ y: -50 }}>
		<main>
			<slot><!-- optional fallback --></slot>
		</main>

		<footer class="footer justify-between p-4 max-w-5xl m-auto mt-3">
			<div class="items-center grid-flow-col">
				<img class="favicon" src="/favicon_shadow.png" alt="Logo" />
				<p>Copyright © {year} - All right reserved</p>
			</div>
			<img
				class="deploy-img"
				src="https://api.netlify.com/api/v1/badges/{PUBLIC_NETLIFY_SITE_ID}/deploy-status"
				alt="Deploy Status Badge"
			/>
		</footer>
	</div>
{/if}
<SvelteToast options={{ duration: 2000 }} />

<style lang="postcss">
	header {
		@apply fixed top-0 bg-base-100  w-full z-10 print:hidden;
	}

	header + * {
		@apply mt-[calc(var(--headerHeight)_+_1rem)];
	}
	nav {
	}
	main {
		@apply max-w-5xl m-auto p-4;
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

	.hover-bounce:hover .bounce {
		animation: bounce 1s infinite;
	}

	.deploy-img {
		@apply hover:scale-95 active:scale-90 transition-all;
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

	footer {
		@apply print:hidden
	}
</style>
