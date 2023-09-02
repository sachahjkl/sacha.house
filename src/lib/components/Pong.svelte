<script lang="ts">
	import { DEFAULTS, init_game_state, scale, type GameState, type InputState } from '$lib/pong';
	import { one_second_in_ms as ONE_SECOND_IN_MS } from '$lib/utils';
	import { onMount } from 'svelte';

	// Game display state
	export let input: InputState;
	export let width = 500; // reference width /!\ DO NOT MUTATE
	export let height = 500; // reference height /!\ DO NOT MUTATE
	export let currentScale = 1;

	// Flags
	export let debug: boolean = false;
	export let playing: boolean = false;
	export let garbageMode: boolean = true;
	export let reset: boolean = false;

	// Error
	export let error: Error | null = null;
	let cause: [boolean, string][];
	$: cause = error?.cause as [boolean, string][];

	let gameState: GameState;

	// Update screen game state when height/width changes from outside (from props)
	$: {
		if (gameState) {
			gameState.screen = { height, width };
			gameState.playing = playing;
		}
	}

	$: console.log('Playing changed !', playing);

	$: {
		console.info('reset', reset);
		if (reset) {
			const state = initGameState();

			if (!state) {
				console.error('failed to init state');
			} else {
				// at this point, we know that state can't be null

				gameState = state;

				state.playing = playing;
			}
		}
	}

	// export let wantedFramerate = 60;

	$: computeScale(width, height);

	let canvas: HTMLCanvasElement;

	const computeScale = (width: number, height: number) => {
		if (typeof window === 'undefined') return;
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

	function initGameState() {
		// We configure our settings
		const mySettings = { ...DEFAULTS };

		mySettings.screen.height = height;
		mySettings.screen.width = width;

		// init game state with our settings (might return a validation error)
		const [state, stateError] = init_game_state(
			mySettings.distanceFromBorder,
			mySettings.dimensions,
			mySettings.screen,
			mySettings.speeds
		);

		// check for error
		if (stateError != null) {
			error = stateError;
			console.error(stateError);
			return;
		}
		return state;
	}

	onMount(() => {
		// We configure our state
		const state = initGameState();

		if (!state) {
			console.error('failed to init state');
			return;
		}

		// at this point, we know that state can't be null
		gameState = state;

		computeScale(width, height);

		// setup scale recompute on window resize
		const dynamicRescale = () => computeScale(width, height);
		window.addEventListener('resize', dynamicRescale);

		const ctx = canvas.getContext('2d');
		if (!ctx) return;

		// keep track of the last time a frame was drawn on the canvas
		// for framerate calculations
		let lastTime = 0;

		// number of boxes to create
		let boxCount = 500;

		// highest color possible
		const MAX_COLOR = parseInt('FFFFFF', 16);

		// the current frame
		let frameHandle: number;

		/**
		 *
		 * @param time current time (in ms)
		 */
		const loop: FrameRequestCallback = (time) => {
			// update game state (Only when playing (ie. not paused))

			// delta (in ms)
			const delta = time - lastTime;

			// tick once
			gameState.tick(delta / ONE_SECOND_IN_MS, input);

			// then scale
			const scaledGameState = scale(state, currentScale);

			const scaledWidth = scaledGameState.screen.width,
				scaledHeight = scaledGameState.screen.height;

			// Draw background
			if (playing) {
				ctx.fillStyle = 'black';
				ctx.fillRect(0, 0, scaledWidth, scaledHeight);
			}

			// Draw silly garbage for fun
			if (playing && garbageMode) {
				const blockSize = 50 * currentScale;
				// Draw some bs to make shit lag
				for (let index = 0; index < boxCount; index++) {
					ctx.fillStyle = `#${Math.round(Math.random() * MAX_COLOR).toString(16)}`;
					ctx.fillRect(
						Math.random() * (scaledWidth - scaledWidth * 0.2 - blockSize) + scaledWidth * 0.1,
						Math.random() * (scaledHeight - scaledHeight * 0.2 - blockSize) + scaledHeight * 0.1,
						blockSize,
						blockSize
					);
				}
			}

			// Set color of elements displayed (for now every element except background is white)
			ctx.fillStyle = 'white';

			// Draw left paddle
			ctx.fillRect(
				scaledGameState.distanceFromBorder,
				scaledGameState.leftPaddle.y,
				scaledGameState.leftPaddle.width,
				scaledGameState.leftPaddle.height
			);
			// Draw right paddle
			ctx.fillRect(
				scaledGameState.screen.width -
					scaledGameState.distanceFromBorder -
					scaledGameState.rightPaddle.width,
				scaledGameState.rightPaddle.y,
				scaledGameState.rightPaddle.width,
				scaledGameState.rightPaddle.height
			);
			// Draw ball
			ctx.fillRect(
				scaledGameState.ball.x,
				scaledGameState.ball.y,
				scaledGameState.ball.width,
				scaledGameState.ball.height
			);

			// Print debug info (overlay)
			if (debug) {
				// Compute & display framerate

				let framerate = '0 fps';

				if (lastTime == 0 || time == 0) {
					framerate = 'N/A';
				} else {
					// display framerate with 1 decimal place
					framerate = `${(ONE_SECOND_IN_MS / delta).toFixed(1)} fps`;
				}

				// update last time since frame was drawn
				lastTime = time;

				// global display settings
				const fontSize = 18;
				const margin = 10;
				const scaledFontSize = fontSize * currentScale;
				const scaledMargin = margin * currentScale;
				ctx.font = `${scaledFontSize}px monospace `;

				// draw framerate
				ctx.fillStyle = 'rgba(255, 255, 0, 0.5)';
				ctx.fillRect(
					scaledMargin - 2,
					scaledMargin,
					scaledFontSize * 5 + 2,
					scaledFontSize + 2 * 2
				);

				ctx.fillStyle = 'black';
				ctx.fillText(framerate, scaledMargin, scaledFontSize + scaledMargin);

				ctx.fillStyle = 'rgba(255, 255, 0, 0.5)';
				ctx.fillRect(
					scaledMargin - 2,
					scaledGameState.screen.height - scaledFontSize - scaledMargin,
					scaledFontSize * 7 + 2,
					scaledFontSize + 2 * 2
				);

				ctx.fillStyle = 'black';
				ctx.fillText(
					`scale=${currentScale.toFixed(2)}`,
					scaledMargin,
					scaledGameState.screen.height - scaledMargin
				);

				// TODO(sacha): maybe assign a specific flag for logging (different from debug)
				// console.table([{ 'time (ms)': time, 'Framerate (img/s)': framerate, delta: delta }]);
			}

			// next frame
			frameHandle = requestAnimationFrame(loop);
		};

		// start loop
		loop(0);

		// cleanup on unMount
		return () => {
			cancelAnimationFrame(frameHandle);
			window.removeEventListener('resize', dynamicRescale);
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
		bind:this={canvas}
		width={width * currentScale}
		height={height * currentScale}
		on:click={() => {
			playing = !playing;
		}}
	/>
{/if}
