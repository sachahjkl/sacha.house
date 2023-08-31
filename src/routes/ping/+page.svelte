<script lang="ts">
	import '$lib/app.css';
	import Pong from '$lib/components/Pong.svelte';

	let play = true;
	let garbageMode = false;
    let debug = false;
</script>

<main class="prose">
	<h1>Pong :</h1>

	<div class="flex justify-center">
		<Pong {play} {garbageMode} {debug} />
	</div>
	<div>
		<label for="hardmode">
			Hardmode (WIP) : <input type="checkbox" name="hardmode" id="hardmode" /></label
		>
	</div>
	<div>
		<label for="play">
			Play : <input type="checkbox" name="play" id="play" bind:checked={play} /></label
		>
	</div>
	<div>
		<label for="garbageMode">
			Garbage Mode : <input
				type="checkbox"
				name="garbageMode"
				id="garbageMode"
				bind:checked={garbageMode}
			/></label
		>
	</div>
	<div>
		<label for="debug">
			Debug info : <input
				type="checkbox"
				name="debug"
				id="debug"
				bind:checked={debug}
			/></label
		>
	</div>
</main>

<style lang="postcss">
	main {
		@apply max-w-5xl m-auto mt-6 p-4;
	}
</style>
