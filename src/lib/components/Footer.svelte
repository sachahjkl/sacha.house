<script lang="ts">
	import { env } from '$env/dynamic/public';

	export let commitHash = 'inconnu';
	const year = new Date().getFullYear();
</script>

<footer class="footer justify-between p-4 max-w-5xl m-auto mt-3">
	<div class="items-center grid-flow-col">
		<slot name="brand">Mon site</slot>
		<p>Copyright © {year} - All right reserved</p>
	</div>
	<div class="flex content-center">
		<img
			class="deploy-img"
			width="135"
			height="20"
			src="https://gitlab.com/{env.PUBLIC_GIT_REPO_ID}/badges/master/pipeline.svg"
			alt="Deploy Status Badge"
		/>
		/
		<a class="underline" href="https://gitlab.com/sachahjkl/sacha.house/-/commit/{commitHash}">
			<small class="text-base-content text-opacity-60">
				commit <b> {commitHash.substring(0, 8)}</b></small
			>
		</a>
	</div>
</footer>

<style lang="postcss">
	footer {
		@apply print:hidden;
	}

	.deploy-img {
		@apply hover:scale-95 active:scale-90 transition-all;
	}
</style>
