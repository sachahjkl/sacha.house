<script lang="ts">
	import type { NavItem } from '$lib/nav';

	export let navItems: NavItem[] = [];
	export let activePagePathname = '';
</script>

<header>
	<nav data-sveltekit-preload-data>
		<ul class="inline-list">
			{#each navItems as item}
				<li>
					<a class:active={activePagePathname === item.pathname} href={item.pathname}>
						{item.icon}
						{item.title}
					</a>
				</li>
			{/each}
		</ul>
	</nav>
</header>
