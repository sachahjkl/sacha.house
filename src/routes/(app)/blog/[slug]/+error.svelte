<script lang="ts">
	import { page } from '$app/stores';
</script>

<article class="prose mx-auto">
	<p class="mb-4">
		<a href="/blog" class=" opacity-60">
			<span class="inline-block rotate-180">➜</span> Go back to the articles list
		</a>
	</p>
	<h1>{$page.status}</h1>
	<p>{$page.error?.message}</p>
</article>
