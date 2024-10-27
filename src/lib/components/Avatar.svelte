<script lang="ts">
	import fallback from '$lib/assets/me.jpg';
	import avif from '$lib/assets/me.jpg?w=200;400;800&format=avif&as=srcset&quality=85&imagetools';
	import webp from '$lib/assets/me.jpg?w=200;400;800&format=webp&as=srcset&quality=85&imagetools';
</script>

<div class="pic">
	<picture>
		<source srcset={avif} type="image/avif" />
		<source srcset={webp} type="image/webp" />
		<img class="me" src={fallback} height="400" width="400" alt="Moi" />
	</picture>
</div>

<style lang="postcss">
	.me,
	picture {
		@apply m-0;
		img {
			@apply m-auto my-4 block border-4 border-textColor;
		}
	}
</style>
