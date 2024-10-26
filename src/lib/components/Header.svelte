<script lang="ts">
	import type { NavItem } from '$lib/nav';

	interface Props {
		navItems?: NavItem[];
		activePagePathname?: string;
		openNav?: boolean;
	}

	let { navItems = [], activePagePathname = '', openNav = $bindable(false) }: Props = $props();
</script>

<header class="p-3 sticky top-0 z-10 bg-bgColor">
	<nav data-sveltekit-preload-data>
		<fieldset class="border-2 p-2 px-4 border-textColor">
			<legend class="px-2 ml-3">Navigation</legend>
			<ul class="gap-3 flex-wrap whitespace-nowrap hidden sm:flex">
				{#each navItems as item, i}
					<li class="sm:flex-none flex-[100%]">
						<a class:active={activePagePathname === item.pathname} href={item.pathname}>
							{item.icon}
							{item.title}
						</a>
					</li>
					{#if i != navItems.length - 1}
						<li class="border-r-2 border-textColor hidden sm:inline-block"></li>
					{/if}
				{/each}
			</ul>

			<details class="sm:hidden block" bind:open={openNav}>
				<summary class="mb-1" >{openNav ? 'open' : 'closed'}</summary>
				<ul class="flex gap-3 flex-wrap whitespace-nowrap">
					{#each navItems as item, i}
						<li class="sm:flex-none flex-[100%]">
							<a class:active={activePagePathname === item.pathname} href={item.pathname}>
								{item.icon}
								{item.title}
							</a>
						</li>
						{#if i != navItems.length - 1}
							<li class="border-r-2 border-textColor hidden sm:inline-block"></li>
						{/if}
					{/each}
				</ul>
			</details>
		</fieldset>
	</nav>
</header>

<style lang="postcss">
	* {
		scrollbar-width: thin;
	}

	a:hover,
	a.active {
		@apply bg-textColor text-bgColor;
	}
</style>
