<script lang="ts">
	import type { NavItem } from '$lib/nav';
	import { onMount } from 'svelte';
	import { themeChange } from 'theme-change';
	import HamburgerIcon from './HamburgerIcon.svelte';

	export let navItems: NavItem[] = [];
	export let activePagePathname = '';
	onMount(() => themeChange(false));
</script>

<header>
	<nav data-sveltekit-preload-data>
		<ul class="inline-list">
			<li class="title md:order-first ">
				<slot name="brand">Brand</slot>
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
							<a class:active={activePagePathname === item.pathname} href={item.pathname}>
								{item.icon}
								{item.title}
							</a>
						</li>
					{/each}
					<li class="select-none flex items-center hover-bounce">
						<form class="w-full">
							<label class="sr-only" for="theme-toggle-dropdown">Choix du thème</label>
							<span class="bounce">🌚</span>
							<input
								type="checkbox"
								data-toggle-theme="light,dark"
								data-act-class="ACTIVECLASS"
								name="theme-toggle-dropdown"
								id="theme-toggle-dropdown"
								class="toggle toggle-sm"
							/> <span class="bounce">🌞</span>
						</form>
					</li>
				</ul>
			</li>
			{#each navItems as item}
				<li class="item-inline">
					<a class:active={activePagePathname === item.pathname} href={item.pathname}>
						{item.icon}
						{item.title}
					</a>
				</li>
			{/each}

			<li class="hidden md:flex items-center select-none hover-bounce">
				<label class="sr-only" for="theme-toggle">Choix du thème</label>
				<span class="bounce">🌚</span>
				<input
					type="checkbox"
					data-toggle-theme="light,dark"
					data-act-class="ACTIVECLASS"
					name="theme-toggle"
					id="theme-toggle"
					class="toggle toggle-sm mx-2"
				/> <span class="bounce">🌞</span>
			</li>
		</ul>
	</nav>
</header>

<style lang="postcss">
	header {
		@apply sticky p-2 top-0 bg-base-100 bg-opacity-50 backdrop-blur-md w-full z-10 print:hidden;
	}
	nav {
		@apply flex flex-wrap justify-between;
	}

	.active {
		@apply font-bold;
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
</style>
