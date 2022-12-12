// See https://kit.svelte.dev/docs/types#app
// for information about these interfaces
// and what to do when importing types

declare namespace App {
	// interface Locals {}
	// interface PageData {}
	// interface Error {}
	// interface Platform {}
}

// Workaround for imagetools imports - https://github.com/microsoft/TypeScript/issues/38638#issuecomment-1088247956
declare module '*&imagetools' {
	const out;
	export default out;
}
