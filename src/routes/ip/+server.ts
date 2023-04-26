export const GET = async ({ fetch }) => {
	return new Response(await fetch('/api/ip').then((res) => res.text()));
};
