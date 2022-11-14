<script lang="ts">
	import avif from '$lib/assets/c-omrade.jpg?w=500;900;1000&avif&srcset&quality=85&imagetools';
	import webp from '$lib/assets/c-omrade.jpg?w=500;900;1000&webp&srcset&quality=85&imagetools';
	import fallback from '$lib/assets/c-omrade.jpg?w=700&quality=85&imagetools';
</script>

<picture>
	<source srcset={avif} type="image/avif" />
	<source srcset={webp} type="image/webp" />
	<img class="illustration" src={fallback} width="1000" height="1305" alt="comrade" />
</picture>

<style lang="postcss">
	.illustration {
		@apply max-w-md w-full m-auto hover:scale-95
		active:scale-90 transition-all;
	}
</style>
