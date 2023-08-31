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

export interface Paddle {
	x: number;
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
	screen: Screen;
	dimensions: Dimensions;
	leftPaddle: Paddle;
	rightPaddle: Paddle;
	ball: Ball;
	tick: (delta: number) => void;
}

export function init_game_state(
	distanceFromBorder: number = DEFAULTS.distanceFromBorder,
	dimensions: {
		ball: number;
		paddle: PaddleDimensions;
	} = DEFAULTS.dimensions,
	screen: Screen = DEFAULTS.screen
): [GameState, null] | [null, Error] {
	const computedState: GameState = {
		dimensions,
		screen,
		ball: {
			x: (screen.width - dimensions.ball) / 2,
			y: (screen.height - dimensions.ball) / 2
		},
		leftPaddle: {
			x: distanceFromBorder,
			y: (screen.height - dimensions.paddle.height) / 2,
			score: 0
		},
		rightPaddle: {
			x: screen.width - distanceFromBorder - dimensions.paddle.width, // needs to be >0
			y: (screen.height - dimensions.paddle.height) / 2,
			score: 0
		},
		tick(delta) {
			delta + 1;
			return;
		}
	};

	// checks
	const constraints: Array<[boolean, string]> = [
		[computedState.screen.height > 100, 'screen needs to be at least 100px high'],
		[computedState.screen.width > 100, 'screen needs to be at least 100px wide'],
		[
			computedState.dimensions.paddle.height < computedState.screen.height / 2,
			'paddles need to take less than 1/2 of the screen height'
		],
		[
			computedState.dimensions.paddle.width < computedState.screen.height / 5,
			'paddles need to take less than 1/5 of the screen height'
		],
		[
			computedState.dimensions.ball < computedState.screen.width / 2 &&
				computedState.dimensions.ball < computedState.screen.height / 2,
			'ball needs to be at most 1/3 the screen size'
		],
		[
			computedState.ball.x > 0 &&
				computedState.ball.x < computedState.screen.height &&
				computedState.ball.y > 0 &&
				computedState.ball.y < computedState.screen.height,
			'ball needs to be in the screen'
		]
	];

	const constraintsAreValid = constraints
		.map((it) => it[0])
		.reduce((acc, current) => acc && current);
	if (!constraintsAreValid) {
		return [
			null,
			Error(
				`Abort. Generated game state would be invalid.\nCause: ${JSON.stringify(
					constraints,
					undefined,
					' '
				)}`
			)
		];
	}

	// we passed checks, we can return the computed state
	return [computedState, null];
}
