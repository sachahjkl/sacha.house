<script lang="ts">
	import { env } from '$env/dynamic/public';
	import ExternalLinkIcon from '$lib/icons/ExternalLinkIcon.svelte';

	export let commitHash = 'unknown';
	const year = new Date().getFullYear();
</script>

<footer
	class="bg-textColor gap-2 text-sm text-bgColor flex flex-wrap items-center justify-between px-2 py-1 font-bold fixed bottom-0 w-full"
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
				height="15"
				src="https://gitlab.com/{env.PUBLIC_GIT_REPO_ID}/badges/master/pipeline.svg"
				alt="Deploy Status Badge"
			/>
			<span>/</span>
			{commitHash.substring(0, 8)}
			<ExternalLinkIcon />
		</div>
	</a>
</footer>

<style>
</style>
