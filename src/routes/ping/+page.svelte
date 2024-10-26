<script lang="ts">
	import '$lib/app.css';
	import Pong from '$lib/components/Pong.svelte';
	import { DEFAULTS, DEFAULT_INPUT_STATE } from '$lib/pong';
	import { throttle } from '$lib/utils';
	import { onMount } from 'svelte';
	import { slide } from 'svelte/transition';
	import { themeChange } from 'theme-change';

	let playing = $state(true);
	let garbageMode = $state(false);
	let debug = $state(true);
	let error: Error | null = $state(null);
	let reset = $state(false);

	let height: number = $state(DEFAULTS.screen.height);
	let width: number = $state(DEFAULTS.screen.width);

	let currentScale: number = $state();

	let input = $state({ ...DEFAULT_INPUT_STATE });

	const KEYS = {
		player1: {
			UP: 'z',
			DOWN: 's',
			LEFT: 'q',
			RIGHT: 'd'
		},
		player2: {
			UP: 'ArrowUp',
			DOWN: 'ArrowDown',
			LEFT: 'ArrowLeft',
			RIGHT: 'ArrowRight'
		},
		START: ' ', // spacebar - start game
		PAUSE: 'p', // p - pause
		RESET: 'r' // r - reset
	};
	const PAUSE_TIMEOUT_MS = 250;
	const RESET_TIMEOUT_MS = 250;
	let pauseTimeout: number = 0;
	let resetTimeout: number = 0;

	const updateInput = (currentKey: string, state = false) => {
		switch (currentKey) {
			case KEYS.player1.UP:
				input.player1.UP = state;
				break;
			case KEYS.player1.DOWN:
				input.player1.DOWN = state;
				break;
			case KEYS.player2.UP:
				input.player2.UP = state;
				break;
			case KEYS.player2.DOWN:
				input.player2.DOWN = state;
				break;
			case KEYS.START:
				input.START = state;
				break;
			case KEYS.PAUSE:
				if (pauseTimeout) return;
				pauseTimeout = setTimeout(() => (pauseTimeout = 0), PAUSE_TIMEOUT_MS);
				playing = !playing;
				break;
			case KEYS.RESET:
				throttle(() => {
					reset = true;
					setTimeout(() => (reset = false), 10);
				}, RESET_TIMEOUT_MS);
				break;
			default:
				return false;
		}
		console.info(input, input.player1, input.player1.UP);
		return true;
	};

	const handleInputDown = (e: KeyboardEvent) => {
		if (updateInput(e.key, true)) {
			e.preventDefault();
		}
	};
	const handleInputUp = (e: KeyboardEvent) => {
		if (updateInput(e.key, false)) {
			e.preventDefault();
		}
	};

	onMount(() => {
		themeChange(false);
		window.addEventListener('keydown', handleInputDown, false);
		window.addEventListener('keyup', handleInputUp, false);
		// window.addEventListener('keydown', handlePause, false);
		return () => {
			window.removeEventListener('keydown', handleInputDown, false);
			window.removeEventListener('keyup', handleInputUp, false);
			// window.addEventListener('keydown', handlePause);
		};
	});
</script>

<svelte:head>
	<title>Ping 👉 Pong</title>
</svelte:head>

<main >
	<p>
		<a class=" opacity-60" href="/" title="Home"
			><span class="rotate-180 inline-block">➜</span> 🏡 Retour à l'accueil</a
		>
	</p>
	<h1 class="text-3xl font-bold mb-[1em]">Pong :</h1>

	<div class="mb-[1em] flex gap-[1em]">
		<button
			class="bg-textColor text-bgColor px-2"
			title="Click to pause the game (or click on the game itself)"
			onclick={() => (playing = !playing)}
		>
			{playing ? '⏸ Pause' : '▶ Play '}
		</button>
		<button
			class="bg-textColor text-bgColor px-2"
			title="Reset the game"
			onclick={throttle(function () {
				console.log('test');
			}, 1000)}>🔄 Reset</button
		>
	</div>
	<div class="flex place-content-center mb-4">
		<div class="ctnr relative transition bg-black shadow-xl border-yellow-500 border-4">
			<Pong
				bind:error
				bind:input
				bind:playing
				bind:height
				bind:width
				bind:currentScale
				{reset}
				{garbageMode}
				{debug}
			/>

			{#if !playing}
				<span
					transition:slide
					class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-full font-bold text-3xl text-white z-10 p-2 text-shadow-xl shadow-red-500/50"
					>PAUSED</span
				>
			{/if}
		</div>
	</div>
	<!-- <div>
		<label for="hardmode">
			Hardmode (WIP) : <input type="checkbox" name="hardmode" id="hardmode" /></label
			>
		</div> -->
	{#if !error}
		<div class="flex justify-items-stretch flex-wrap">
			<div id="settings" class="flex-grow flex-shrink basis-[400px]">
				<h2 class="text-2xl font-bold mb-2">Settings</h2>

				<div class="flex gap-2 flex-col">
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
						Debug info: <input
							type="checkbox"
							name="debug"
							id="debug"
							bind:checked={debug}
						/></label
					>
					<label for="scale">
						Scale: <input
							class="px-2"
							type="text"
							name="scale"
							id="scale"
							readonly
							bind:value={currentScale}
						/></label
					>
				</div>
			</div>
			<div id="instructions" class="flex-grow flex-shrink basis-[400px]">
				<h2>Instructions</h2>
				<div class="flex flex-wrap gap-4">
					<section class="basis-52 p-4 shadow-sm rounded">
						<h3>Général</h3>

						<ul class="list-none p-0">
							<li>Start : <kbd class="kbd kdb-sm">{KEYS.START.replace(' ', '␣')}</kbd></li>
							<li>Pause : <kbd class="kbd kdb-sm">{KEYS.PAUSE}</kbd></li>
							<li>Reset : <kbd class="kbd kdb-sm">{KEYS.RESET}</kbd></li>
						</ul>
					</section>
					<section class="basis-52 p-4 shadow-sm rounded">
						<h3>Joueur 1</h3>
						<ul class="list-none p-0">
							<li>
								HAUT : <kbd class="kbd kbd-sm">{KEYS.player1.UP}</kbd>
							</li>
							<li>BAS : <kbd class="kbd kbd-sm">{KEYS.player1.DOWN}</kbd></li>
						</ul>
					</section>
					<section class="basis-52 p-4 shadow-sm rounded">
						<h3>Joueur 2</h3>
						<ul class="list-none p-0">
							<li>HAUT : <kbd class="kbd kbd-sm">{KEYS.player2.UP}</kbd></li>
							<li>BAS : <kbd class="kbd kbd-sm">{KEYS.player2.DOWN}</kbd></li>
						</ul>
					</section>
				</div>
			</div>
		</div>
	{/if}
</main>

<style lang="postcss">
	main {
		@apply max-w-5xl m-auto mt-6 p-4;
	}
	#instructions h3 {
		@apply mt-0;
	}
</style>
