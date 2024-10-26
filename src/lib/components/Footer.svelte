<script lang="ts">
	import { env } from '$env/dynamic/public';

	export let commitHash = 'inconnu';
	const year = new Date().getFullYear();
</script>

<footer class="bg-textColor text-bgColor flex items-center justify-between px-2 py-1 font-bold"> 
	<div class="">
		<p>(C) 2024</p>
	</div>
	<div class="flex flex-wrap items-center gap-3">
		<img
			class="deploy-img"
			width="135"
			height="20"
			src="https://gitlab.com/{env.PUBLIC_GIT_REPO_ID}/badges/master/pipeline.svg"
			alt="Deploy Status Badge"
		/>
		/
		<a  href="https://gitlab.com/sachahjkl/sacha.house/-/commit/{commitHash}"> 
			<small class=" text-opacity-60">
				commit <b> {commitHash.substring(0, 8)}</b></small
			>
		</a>
	</div>
</footer>

