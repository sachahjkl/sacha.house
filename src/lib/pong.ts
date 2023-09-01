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
		width: 500
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
	}
};

export const KEYS = {
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
	}
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
}

export interface Paddle {
	y: number;
	score: number;
}

export interface Ball {
	x: number;
	y: number;
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
	distanceFromBorder: number;
	screen: Screen;
	dimensions: Dimensions;
	leftPaddle: Paddle;
	rightPaddle: Paddle;
	ball: Ball;
	tick: (delta: number, input: InputState) => void;
}

const constraints: (state: GameState) => Array<[boolean, string]> = (state) => [
	[state.screen.height > 100, 'screen needs to be at least 100px high'],
	[state.screen.width > 100, 'screen needs to be at least 100px wide'],
	[
		state.dimensions.paddle.height < state.screen.height / 2,
		'paddles need to take less than 1/2 of the screen height'
	],
	[
		state.dimensions.paddle.width < state.screen.height / 5,
		'paddles need to take less than 1/5 of the screen height'
	],
	[
		state.dimensions.ball < state.screen.width / 2 &&
			state.dimensions.ball < state.screen.height / 2,
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
	screen: Screen = DEFAULTS.screen
): [GameState, null] | [null, Error] {
	const state: GameState = {
		distanceFromBorder,
		dimensions,
		screen,
		ball: {
			x: (screen.width - dimensions.ball) / 2,
			y: (screen.height - dimensions.ball) / 2
		},
		leftPaddle: {
			// x: distanceFromBorder,
			y: (screen.height - dimensions.paddle.height) / 2, // start the paddle in middle of the screen (height-wise)
			score: 0
		},
		rightPaddle: {
			// x: screen.width - distanceFromBorder - dimensions.paddle.width, // needs to be >0
			y: (screen.height - dimensions.paddle.height) / 2, // start the paddle in middle of the screen (height-wise)
			score: 0
		},
		tick(delta, input) {
			console.log(input.player1.UP);
			delta + 1;
			return;
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
		distanceFromBorder: state.distanceFromBorder * scale,
		ball: {
			x: state.ball.x * scale,
			y: state.ball.y * scale
		},
		dimensions: {
			ball: state.dimensions.ball * scale,
			paddle: {
				height: state.dimensions.paddle.height * scale,
				width: state.dimensions.paddle.width * scale
			}
		},
		leftPaddle: {
			...state.leftPaddle,
			y: state.leftPaddle.y * scale
		},
		rightPaddle: {
			...state.rightPaddle,
			y: state.rightPaddle.y * scale
		},
		screen: {
			height: state.screen.height * scale,
			width: state.screen.width * scale
		},
		tick: state.tick
	};
}
