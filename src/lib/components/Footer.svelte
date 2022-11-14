<script lang="ts">
	export let commitHash = 'inconnu';
	export let netlifyID = '';
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
			src="https://api.netlify.com/api/v1/badges/{netlifyID}/deploy-status"
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
