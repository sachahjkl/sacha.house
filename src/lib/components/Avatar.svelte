<script lang="ts">
	import fallback from '$lib/assets/me.jpg';
	import avif from '$lib/assets/me.jpg?w=200;400;800&format=avif&as=srcset&quality=85&imagetools';
	import webp from '$lib/assets/me.jpg?w=200;400;800&format=webp&as=srcset&quality=85&imagetools';
</script>

<div class="pic">
	<picture>
		<source srcset={avif} type="image/avif" />
		<source srcset={webp} type="image/webp" />
		<img class="me" src={fallback} height="800" width="800" alt="Moi" />
	</picture>
</div>

<style lang="postcss">
	.pic {
		@apply w-80 mx-auto rounded-full ring-4 hover:ring-8
		hover:ring-secondary hover:scale-105 active:ring-success active:scale-95
		transition-all ring-primary ring-offset-base-100 ring-offset-2;
	}
	.me, picture {
		@apply m-0;
	}
</style>
