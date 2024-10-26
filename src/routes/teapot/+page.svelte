<script lang="ts">
	export let data;
	const randomSpewage = (Math.random() + 1).toString(36).substring(7);
</script>

<p>
	<a href="/" class=" opacity-60">
		<span class="rotate-180 inline-block">➜</span> Home</a
	>
</p>
<h1>Here, let's make you a nice cup of :</h1>

<ul>
	<li><a href="?drink=tea">Tea</a></li>
	<li><a href="?drink=coffee">Coffee</a></li>
	<li><a href="?drink={randomSpewage}">Random spewage</a></li>
</ul>
{#if data.brewMessage}
	<hr />
	<p class="text-4xl text-center font-black">
		{data.brewMessage.text}
	</p>
	<p class="text-center text-9xl mt-20 animate-bounce drop-shadow-md">
		{data.brewMessage.emoji}
	</p>
{/if}
