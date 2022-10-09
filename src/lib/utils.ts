import chroma from 'chroma-js';

export function capitalize(s: string) {
	return s[0].toUpperCase() + s.slice(1);
}

export const randomColor = () => {
	// 30 random hues with step of 12 degrees
	const h = Math.floor((Math.random() * 360) / 12) * 12;

	return chroma.hsl(h, 0.9, 0.6).hex();
};
