export function capitalize(s: string) {
	return s[0].toUpperCase() + s.slice(1);
}

export const randomColorHSL = () => {
	// 30 random hues with step of 12 degrees
	const h = Math.floor((Math.random() * 360) / 12) * 12;

	return [h, 0.9, 0.6];
};
