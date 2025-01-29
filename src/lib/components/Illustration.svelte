<script lang="ts">
	import avif from '$lib/assets/c-omrade.jpg?w=500;900;1000&format=avif&as=srcset&quality=85&imagetools';
	import webp from '$lib/assets/c-omrade.jpg?w=500;900;1000&format=webp&as=srcset&quality=85&imagetools';
	import fallback from '$lib/assets/c-omrade.jpg?w=700&quality=85&imagetools';
</script>

<picture>
	<source srcset={avif} type="image/avif" />
	<source srcset={webp} type="image/webp" />
	<img class="m-auto w-full max-w-md" src={fallback} width="1000" height="1305" alt="comrade" />
</picture>

