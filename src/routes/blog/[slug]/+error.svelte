<script lang="ts">
	import { page } from '$app/stores';
</script>

<article class="prose mx-auto">
	<p>
		<a href="/blog" class="text-base-content opacity-60">
			<span class="rotate-180 inline-block">➜</span> Retour à la liste des articles
		</a>
	</p>
	<h1>{$page.status}</h1>
	<p>{$page.error?.message}</p>
</article>
