<script lang="ts">
	import '$lib/app.css';
	import Pong from '$lib/components/Pong.svelte';
	import { DEFAULT_INPUT_STATE, KEYS } from '$lib/pong';
	import { onMount } from 'svelte';

	let play = true;
	let garbageMode = false;
	let debug = false;
	let error: Error | null = null;

	let height: number;
	let width: number;

	let input = DEFAULT_INPUT_STATE;

	const handleInputDown = (e: KeyboardEvent) => {
		// console.log(e.key)

		switch (e.key) {
			case KEYS.player1.UP:
				input.player1.UP = true;
				break;
			case KEYS.player1.DOWN:
				input.player1.DOWN = true;
				break;
			case KEYS.player2.UP:
				input.player2.UP = true;
				break;
			case KEYS.player2.DOWN:
				input.player2.DOWN = true;
				break;
			default:
				break;
		}
	};
	const handleInputUp = (e: KeyboardEvent) => {
		// console.log(e.key)

		switch (e.key) {
			case KEYS.player1.UP:
				input.player1.UP = false;
				break;
			case KEYS.player1.DOWN:
				input.player1.DOWN = false;
				break;
			case KEYS.player2.UP:
				input.player2.UP = false;
				break;
			case KEYS.player2.DOWN:
				input.player2.DOWN = false;
				break;
			default:
				break;
		}
	};

	onMount(() => {
		window.addEventListener('keydown', handleInputDown);
		window.addEventListener('keyup', handleInputUp);
		return () => {
			window.removeEventListener('keydown', handleInputDown);
			window.removeEventListener('keydown', handleInputUp);
		};
	});
</script>

<main class="prose">
	<h1>Pong :</h1>

	<div class="flex place-content-center">
		<Pong bind:error bind:input {play} bind:height bind:width {garbageMode} {debug} />
	</div>
	<!-- <div>
		<label for="hardmode">
			Hardmode (WIP) : <input type="checkbox" name="hardmode" id="hardmode" /></label
			>
		</div> -->
	{#if !error}
		<div id="settings">
			<h2>Settings</h2>

			<div class="flex gap-2 flex-col">
				<label for="play">
					Play : <input type="checkbox" name="play" id="play" bind:checked={play} />
				</label>

				<label for="height">
					Height:
					<input
						type="range"
						min="250"
						max="1000"
						step="50"
						id="height"
						name="height"
						bind:value={height}
					/>
					({height})
				</label>

				<label for="width">
					Width:
					<input
						type="range"
						min="250"
						max="1000"
						step="50"
						id="width"
						name="width"
						bind:value={width}
					/>
					({width})
				</label>

				<label for="garbageMode">
					Garbage Mode: <input
						type="checkbox"
						name="garbageMode"
						id="garbageMode"
						bind:checked={garbageMode}
					/></label
				>

				<label for="debug">
					Debug info: <input type="checkbox" name="debug" id="debug" bind:checked={debug} /></label
				>
			</div>
		</div>
	{/if}
</main>

<style lang="postcss">
	main {
		@apply max-w-5xl m-auto mt-6 p-4;
	}
</style>
