<script lang="ts">
	import { DEFAULTS, init_game_state } from '$lib/pong';
	import { onMount } from 'svelte';

	export let width = 500;
	export let height = 500;
	export let play: boolean = true;
	export let garbageMode: boolean = true;
	export let debug: boolean = false;
	// export let wantedFramerate = 60;

	let canvas: HTMLCanvasElement;

	onMount(() => {
		const [gameState, error] = init_game_state(
			DEFAULTS.distanceFromBorder,
			DEFAULTS.dimensions,
			DEFAULTS.screen
		);
		if (error != null) {
			console.error(error);
			return;
		}

        // scale down the render for mobile
		const widthRatio = window.innerWidth / gameState.screen.width;
		const heightRatio = window.innerHeight / gameState.screen.width;
		const minRatio = Math.min(widthRatio, heightRatio);
		if (minRatio < 1) {
			canvas.style.transform = `scale(${Math.floor(minRatio * 10) / 10})`;
		}

		// at this point, we know that gameState can't be null

		const ctx = canvas.getContext('2d');
		if (!ctx) return;

		// keep track of the last time a frame was drawn on the canvas
		// for framerate calculations
		let lastTime = 0;

		let count = 5000;

		const MAX_COLOR = parseInt('FFFFFF', 16);
		const one_second_in_ms = 1000;

		/**
		 *
		 * @param time current time (in ms)
		 */
		const loop: FrameRequestCallback = (time) => {
			// Draw background
			ctx.fillStyle = 'black';
			ctx.fillRect(0, 0, width, height);

			// Print debug info
			if (debug) {
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
				// draw some bs to make shit lag
				for (let index = 0; index < count; index++) {
					ctx.fillStyle = `#${Math.round(Math.random() * MAX_COLOR).toString(16)}`;
					ctx.fillRect(
						Math.random() * (height - 150) + 50,
						Math.random() * (width - 150) + 50,
						50,
						50
					);
				}
			}

			if (play) {
				ctx.fillStyle = 'white';
				// draw left paddle
				ctx.fillRect(
					gameState.leftPaddle.x,
					gameState.leftPaddle.y,
					gameState.dimensions.paddle.width,
					gameState.dimensions.paddle.height
				);
				// draw right paddle
				ctx.fillRect(
					gameState.rightPaddle.x,
					gameState.rightPaddle.y,
					gameState.dimensions.paddle.width,
					gameState.dimensions.paddle.height
				);
				// draw ball
				ctx.fillRect(
					gameState.ball.x,
					gameState.ball.y,
					gameState.dimensions.ball,
					gameState.dimensions.ball
				);
			}
			// next frame
			requestAnimationFrame(loop);
		};

		// start loop
		loop(0);
	});
</script>

<canvas class="block border rounded shadow" bind:this={canvas} {width} {height} />
