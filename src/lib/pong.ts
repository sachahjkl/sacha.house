import { clamp } from './utils';

export const DEFAULTS = {
	dimensions: {
		paddle: {
			height: 200,
			width: 40
		},
		ball: 20
	},
	distanceFromBorder: 20,
	screen: {
		height: 500,
		width: 950
	},
	speeds: {
		paddle: 300, // pixels per second
		ball: 300 // pixels per second
	}
};

export const DEFAULT_INPUT_STATE: InputState = {
	player1: {
		UP: false,
		DOWN: false
	},
	player2: {
		UP: false,
		DOWN: false
	},
	START: false,
	PAUSE: false
};

export interface InputState {
	player1: {
		UP: boolean;
		DOWN: boolean;
		// LEFT: 'q',
		// RIGHT: 'd'
	};
	player2: {
		UP: boolean;
		DOWN: boolean;
		// LEFT: boolean,
		// RIGHT: boolean
	};
	START: boolean;
	PAUSE: boolean;
}

export interface Paddle {
	y: number;
	speed: number;
	score: number;
	height: number;
	width: number;
}

export interface Ball {
	x: number;
	y: number;
	height: number;
	width: number;
	speed: {
		vx: number;
		vy: number;
	};
}

export interface Screen {
	height: number;
	width: number;
}

export interface Dimensions {
	ball: number;
	paddle: PaddleDimensions;
}

export interface PaddleDimensions {
	height: number;
	width: number;
}

export interface GameState {
	started: boolean;
	playing: boolean;
	distanceFromBorder: number;
	screen: Screen;
	leftPaddle: Paddle;
	rightPaddle: Paddle;
	ball: Ball;
	tick: (delta: number, input: InputState) => void;
}

const constraints: (state: GameState) => Array<[boolean, string]> = (state) => [
	[state.screen.height > 100, 'screen needs to be at least 100px high'],
	[state.screen.width > 100, 'screen needs to be at least 100px wide'],
	[
		state.leftPaddle.width < state.screen.width / 5 &&
			state.rightPaddle.width < state.screen.width / 5,
		'paddles need to take less than 1/5 of the screen height'
	],
	[
		state.leftPaddle.height < state.screen.height / 2 &&
			state.rightPaddle.height < state.screen.height / 2,
		'paddles need to take less than 1/2 of the screen height'
	],
	[
		state.ball.width < state.screen.width / 2 && state.ball.height < state.screen.height / 2,
		'ball needs to be at most 1/3 the screen size'
	],
	[
		state.ball.x > 0 &&
			state.ball.x < state.screen.height &&
			state.ball.y > 0 &&
			state.ball.y < state.screen.height,
		'ball needs to be in the screen'
	]
];

/**
 *
 * @param distanceFromBorder how much distance between the borders and the paddle
 * @param dimensions dimensions of ball & paddles
 * @param screen dimensions of the screen
 * @returns if the validation failed, returns a `null` game state object and an
 * error object containing the reasons why the validation failed.
 *
 * Otherwise returns a game state object and no error (similar to the `Result`
 * pattern)
 */
export function init_game_state(
	distanceFromBorder: number = DEFAULTS.distanceFromBorder,
	dimensions: {
		ball: number;
		paddle: PaddleDimensions;
	} = DEFAULTS.dimensions,
	screen: Screen = DEFAULTS.screen,
	speeds = DEFAULTS.speeds
): [GameState, null] | [null, Error] {
	const state: GameState = {
		started: false,
		playing: false,
		distanceFromBorder,
		screen,
		ball: {
			speed: {
				vx: speeds.ball,
				vy: speeds.ball
			},
			x: dimensions.paddle.width + distanceFromBorder * 2,
			y: (screen.height - dimensions.ball) / 2,
			height: dimensions.ball,
			width: dimensions.ball
		},
		leftPaddle: {
			width: dimensions.paddle.width,
			height: dimensions.paddle.height,
			speed: speeds.paddle,
			y: (screen.height - dimensions.paddle.height) / 2, // start the paddle in middle of the screen (height-wise)
			score: 0
		},
		rightPaddle: {
			width: dimensions.paddle.width,
			height: dimensions.paddle.height,
			speed: speeds.paddle,
			y: (screen.height - dimensions.paddle.height) / 2, // start the paddle in middle of the screen (height-wise)
			score: 0
		},
		tick(delta, input) {
			// don't run tick if playing is off (paused)
			// console.log('tick', this);
			if (!this.playing) {
				return;
			}

			const oldLeftPaddle = { ...this.leftPaddle };
			// const oldrightPaddle = { ...this.rightPaddle };

			// Start game if not started yet
			if (!this.started && input.START) {
				this.started = true;
			}

			// player 1 / left paddle

			if (input.player1.UP) {
				this.leftPaddle.y -= this.leftPaddle.speed * delta;
			}

			if (input.player1.DOWN) {
				this.leftPaddle.y += this.leftPaddle.speed * delta;
			}

			// clamp
			this.leftPaddle.y = clamp(this.leftPaddle.y, 0, this.screen.height - this.leftPaddle.height);

			// player 2 / right paddle

			if (input.player2.UP) {
				this.rightPaddle.y -= this.rightPaddle.speed * delta;
			}

			if (input.player2.DOWN) {
				this.rightPaddle.y += this.rightPaddle.speed * delta;
			}

			// clamp
			this.rightPaddle.y = clamp(
				this.rightPaddle.y,
				0,
				this.screen.height - this.rightPaddle.height
			);

			// ball
			if (input.player1.UP && !this.started && oldLeftPaddle.y != this.leftPaddle.y) {
				this.ball.y -= this.leftPaddle.speed * delta;
			}

			if (input.player1.DOWN && !this.started && oldLeftPaddle.y != this.leftPaddle.y) {
				this.ball.y += this.leftPaddle.speed * delta;
			}

			// clamp
			this.ball.x = clamp(this.ball.x, 0, this.screen.height - this.ball.height);
			this.ball.y = clamp(this.ball.y, 0, this.screen.width - this.ball.width);
		}
	};

	const computedConstraints = constraints(state);
	// checks
	const constraintsAreValid = computedConstraints
		.map((it) => it[0])
		.reduce((acc, current) => acc && current);
	if (!constraintsAreValid) {
		return [
			null,
			Error(`Abort. Generated game state would be invalid.`, {
				cause: computedConstraints
			})
		];
	}

	// we passed checks, we can return the computed state
	return [state, null];
}

export function scale(state: GameState, scale: number): GameState {
	return {
		started: state.started,
		playing: state.playing,
		distanceFromBorder: state.distanceFromBorder * scale,
		ball: {
			x: state.ball.x * scale,
			y: state.ball.y * scale,
			height: state.ball.height * scale,
			width: state.ball.width * scale,
			speed: {
				vx: state.ball.speed.vx * scale,
				vy: state.ball.speed.vy * scale
			}
		},
		leftPaddle: {
			...state.leftPaddle,
			width: state.leftPaddle.width * scale,
			height: state.leftPaddle.height * scale,
			speed: state.leftPaddle.speed * scale,
			y: state.leftPaddle.y * scale
		},
		rightPaddle: {
			...state.rightPaddle,
			width: state.rightPaddle.width * scale,
			height: state.rightPaddle.height * scale,
			speed: state.rightPaddle.speed * scale,
			y: state.rightPaddle.y * scale
		},
		screen: {
			height: state.screen.height * scale,
			width: state.screen.width * scale
		},
		tick: state.tick
	};
}
