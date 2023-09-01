<script lang="ts">
	import { DEFAULTS, init_game_state, scale, type GameState, type InputState } from '$lib/pong';
	import { onMount } from 'svelte';

	export let width = 500; // reference width /!\ DO NOT MUTATE
	export let height = 500; // reference height /!\ DO NOT MUTATE
	export let play: boolean = true;
	export let garbageMode: boolean = true;
	export let debug: boolean = false;
	export let currentScale = 1;
	export let input : InputState;

	export let error: Error | null = null;

	let cause: [boolean, string][];

	$: cause = error?.cause as [boolean, string][];

	// let scaledHeight: number = height;
	// let scaledWidth: number = width;

	// $: scaledHeight = height * scale;
	// $: scaledWidth = width * scale;
	$: {
		if (gameState) {
			gameState.screen = { height, width };
		}
	}

	let gameState: GameState | null;

	// export let wantedFramerate = 60;

	$: currentScale = 1;

	let canvas: HTMLCanvasElement;

	const rescaleCanvas = () => {
		// no bigger than the current width/height
		let minRatio =
			Math.min(
				window?.innerWidth / width, // width ratio
				window?.innerHeight / height // height ratio,
			) - 0.05;
		if (minRatio < 1) {
			minRatio -= 0.05;
		}

		currentScale = Math.min(1, Math.max(0.2, minRatio));
	};



	onMount(() => {
		// We configure our settings
		const mySettings = DEFAULTS;

		mySettings.screen.height = height;
		mySettings.screen.width = width;

		// init game state with our settings (might return a validation error)
		const [state, stateError] = init_game_state(
			mySettings.distanceFromBorder,
			mySettings.dimensions,
			mySettings.screen
		);

		// check for error
		if (stateError != null) {
			error = stateError;
			console.error(stateError);
			return;
		}

		// at this point, we know that gameState can't be null
		gameState = state;

		rescaleCanvas();

		window.addEventListener('resize', rescaleCanvas);

		const ctx = canvas.getContext('2d');
		if (!ctx) return;

		// keep track of the last time a frame was drawn on the canvas
		// for framerate calculations
		let lastTime = 0;

		let count = 5000;

		const MAX_COLOR = parseInt('FFFFFF', 16);
		const one_second_in_ms = 1000;

		// the current frame
		let frameHandle: number;

		/**
		 *
		 * @param time current time (in ms)
		 */
		const loop: FrameRequestCallback = (time) => {
			const scaledGameState = scale(state, currentScale);

			const scaledWidth = scaledGameState.screen.width,
				scaledHeight = scaledGameState.screen.height;

			// Draw background
			if(play){

				ctx.fillStyle = 'black';
				ctx.fillRect(0, 0, scaledWidth, scaledHeight);
			}

			// Print debug info
			if (play && debug) {
				// Compute & display framerate

				let framerate = '0 fps';
				const delta = time - lastTime;

				if (lastTime == 0 || time == 0) {
					framerate = 'N/A';
				} else {
					// display framerate with 1 decimal place
					framerate = `${(one_second_in_ms / delta).toFixed(1)} fps`;
				}

				// update last time since frame was drawn
				lastTime = time;

				// draw framerate
				ctx.font = 'serif 24px';
				ctx.fillStyle = 'white';
				ctx.fillText(framerate, 10, 10);

				// annoying and slow, only for debug
				// TODO(sacha): maybe assign a specific flag for logging (different from debug)
				// console.table([{ 'time (ms)': time, 'Framerate (img/s)': framerate, delta: delta }]);
			}

			// Draw silly garbage for fun
			if (garbageMode) {
				const blockSize = 50 * currentScale;
				// draw some bs to make shit lag
				for (let index = 0; index < count; index++) {
					ctx.fillStyle = `#${Math.round(Math.random() * MAX_COLOR).toString(16)}`;
					ctx.fillRect(
						Math.random() * (scaledWidth - scaledWidth * 0.2 - blockSize) + scaledWidth * 0.1,
						Math.random() * (scaledHeight - scaledHeight * 0.2 - blockSize) + scaledHeight * 0.1,
						blockSize,
						blockSize
					);
				}
			}

			if (play) {
				// update game state
				scaledGameState.tick(time, input);

				// set color of elements displayed (for now every element except background is white)
				ctx.fillStyle = 'white';

				// draw left paddle
				ctx.fillRect(
					scaledGameState.distanceFromBorder,
					scaledGameState.leftPaddle.y,
					scaledGameState.dimensions.paddle.width,
					scaledGameState.dimensions.paddle.height
				);
				// draw right paddle
				ctx.fillRect(
					scaledGameState.screen.width -
						scaledGameState.distanceFromBorder -
						scaledGameState.dimensions.paddle.width,
					scaledGameState.rightPaddle.y,
					scaledGameState.dimensions.paddle.width,
					scaledGameState.dimensions.paddle.height
				);
				// draw ball
				ctx.fillRect(
					scaledGameState.ball.x,
					scaledGameState.ball.y,
					scaledGameState.dimensions.ball,
					scaledGameState.dimensions.ball
				);
			}
			// next frame
			frameHandle = requestAnimationFrame(loop);
		};

		// start loop
		loop(0);

		// cleanup on unMount
		return () => {
			cancelAnimationFrame(frameHandle);
			window.removeEventListener('resize', rescaleCanvas);
		};
	});
</script>

{#if cause}
	<p>Validation failed :</p>
	<ul>
		{#each cause as check}
			<li><input type="checkbox" checked={check[0]} readonly /> {check[1]}</li>
		{/each}
	</ul>
{:else}
	<canvas
		class="block border rounded shadow"
		bind:this={canvas}
		width={width * currentScale}
		height={height * currentScale}
	/>
{/if}
