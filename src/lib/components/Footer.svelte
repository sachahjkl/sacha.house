<script lang="ts">
	import { env } from '$env/dynamic/public';
	import ExternalLinkIcon from '$lib/icons/ExternalLinkIcon.svelte';
	import type { Snippet } from 'svelte';

	interface FooterProps {
		commitHash?: string;
		children?: Snippet;
	}

	let { commitHash = 'unknown' }: FooterProps = $props();
	const year = new Date().getFullYear();
</script>

<footer
	class="bg-textColor text-bgColor fixed bottom-0 flex w-full flex-wrap items-center justify-between gap-2 px-2 py-1 text-xs font-bold"
>
	<div>
		<p>(C) {year} sacha.house</p>
	</div>
	<a
		class="flex items-center gap-1"
		href="https://gitlab.com/sachahjkl/sacha.house/-/commit/{commitHash}"
	>
		<div class="flex items-center gap-1">
			<img
				width="100"
				src="https://gitlab.com/{env.PUBLIC_GIT_REPO_ID}/badges/master/pipeline.svg"
				alt="Deploy Status Badge"
			/>
			{commitHash.substring(0, 8)}
			<ExternalLinkIcon />
		</div>
	</a>
</footer>

<style>
</style>
