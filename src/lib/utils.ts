export const one_second_in_ms = 1000;

export function clamp(value: number, min: number, max: number) {
	return Math.min(Math.max(value, min), max);
}

export function capitalize(s: string) {
	return s[0].toUpperCase() + s.slice(1);
}

export function throttle(callback: (...args: unknown[]) => unknown, delay: number) {
	let last: number;
	let timer: number;
	return function (this: unknown, ...localArgs: unknown[]) {
		const context: unknown = this as unknown;
		const now = +new Date();
		const args = localArgs;
		if (last && now < last + delay) {
			// le délai n'est pas écoulé on reset le timer
			clearTimeout(timer);
			timer = setTimeout(function () {
				last = now;
				callback.apply(context, args);
			}, delay);
		} else {
			last = now;
			callback.apply(context, args);
		}
	};
}

export function debounce(callback: (...args: unknown[]) => unknown, delay: number) {
	let timer: number;
	return function (this: unknown, ...localArgs: unknown[]) {
		const args = localArgs;
		const context: unknown = this as unknown;
		clearTimeout(timer);
		timer = setTimeout(function () {
			callback.apply(context, args);
		}, delay);
	};
}

let latestHue = 0;
export const randomColorHSL = () => {
	// 30 random hues with step of 12 degrees
	let tmp = latestHue;
	while (tmp == latestHue) {
		tmp = (360 / 12) * Math.round(Math.random() * 12);
	}
	latestHue = tmp;

	return [latestHue, 10, 0.6];
};

export const isChristmas = (givenDate: Date = new Date()) => {
	const today = givenDate || new Date();
	// from November 25th
	const endNovember = new Date(today.getFullYear(), 10, 25);
	// to January 5th
	const startJanuary = new Date(today.getFullYear() + 1, 0, 5);

	const christmasCheck = endNovember <= today && today <= startJanuary;
	console.log('is Christmas: ', christmasCheck, 'start: ', endNovember, 'end: ', startJanuary);

	return christmasCheck;
};

function embRand(a: number, b: number) {
	return Math.floor(Math.random() * (b - a + 1)) + a;
}

// author : https://app.embed.im/snow.js
export const addSnow = (document: Document) => {
	let embedimSnow = document.getElementById('embedim--snow');
	if (!embedimSnow) {
		let embCSS =
			'.embedim-snow{position: absolute;width: 20px;height: 20px;background: white;border-radius: 50%;margin-top:-10px; border: 2px solid rgba(0,0,0,0.3); filter: drop-shadow(0 4px 3px rgb(0 0 0 / 0.07)) drop-shadow(0 2px 2px rgb(0 0 0 / 0.06));}';
		let embHTML = '';
		for (let n = 1; n < 200; n++) {
			const i = n + 1;

			embHTML += '<i class="embedim-snow"></i>';
			const rndX = embRand(0, 1000000) * 0.0001,
				rndO = embRand(-100000, 100000) * 0.0001,
				rndT = (embRand(3, 8) * 10).toFixed(2),
				rndS = (embRand(0, 10000) * 0.0001).toFixed(2);
			embCSS += `.embedim-snow:nth-child(${i}){opacity:${(embRand(1, 10000) * 0.0001).toFixed(
				2
			)};transform:translate(${rndX.toFixed(
				2
			)}vw,-10px) scale(${rndS});animation:fall-${i} ${embRand(10, 30)}s -${embRand(
				0,
				30
			)}s linear infinite}@keyframes fall-${i}{${rndT}%{transform:translate(${(rndX + rndO).toFixed(
				2
			)}vw,${rndT}vh) scale(${rndS})}to{transform:translate(${(rndX + rndO / 2).toFixed(
				2
			)}vw, 105vh) scale(${rndS})}}`;
		}
		embedimSnow = document.createElement('div');
		embedimSnow.id = 'embedim--snow';
		embedimSnow.innerHTML =
			'<style>#embedim--snow{position:fixed;left:0;top:0;bottom:0;width:100vw;height:100vh;overflow:hidden;z-index:9999999;pointer-events:none}' +
			embCSS +
			'</style>' +
			embHTML;
		document.body.appendChild(embedimSnow);
	}
};

export const statusCodeToText = (status: number) => {
	switch (status) {
		case 418:
			return "I'm a teapot";

		default:
			return 'Unknown';
	}
};
