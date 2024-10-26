<script lang="ts">
	import { page } from '$app/stores';
</script>

<article class="prose mx-auto">
	<p>
		<a href="/blog" class=" opacity-60">
			<span class="rotate-180 inline-block">➜</span> Go back to the articles list
		</a>
	</p>
	<h1>{$page.status}</h1>
	<p>{$page.error?.message}</p>
</article>
