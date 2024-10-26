<script lang="ts">
	import type { NavItem } from '$lib/nav';

	interface Props {
		navItems?: NavItem[];
		activePagePathname?: string;
		openNav?: boolean;
	}

	let { navItems = [], activePagePathname = '', openNav = $bindable(false) }: Props = $props();
</script>

<header class="sticky top-0 z-10 bg-bgColor p-3">
	<nav data-sveltekit-preload-data>
		<fieldset class="border-2 border-textColor p-2 px-4">
			<legend class="ml-3 px-2">Navigation</legend>
			<ul class="hidden flex-wrap gap-3 whitespace-nowrap sm:flex">
				{#each navItems as item, i}
					<li class="flex-[100%] sm:flex-none">
						<a class:active={activePagePathname === item.pathname} href={item.pathname}>
							{item.icon}
							{item.title}
						</a>
					</li>
					{#if i != navItems.length - 1}
						<li class="hidden border-r-2 border-textColor sm:inline-block"></li>
					{/if}
				{/each}
			</ul>

			<details class="block sm:hidden" bind:open={openNav}>
				<summary class="mb-1">{openNav ? 'open' : 'closed'}</summary>
				<ul class="flex flex-wrap gap-3 whitespace-nowrap">
					{#each navItems as item, i}
						<li class="flex-[100%] sm:flex-none">
							<a class:active={activePagePathname === item.pathname} href={item.pathname}>
								{item.icon}
								{item.title}
							</a>
						</li>
						{#if i != navItems.length - 1}
							<li class="hidden border-r-2 border-textColor sm:inline-block"></li>
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
