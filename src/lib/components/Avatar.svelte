<script lang="ts">
	import avif from '$lib/assets/me.jpg?w=200;400;800&avif&srcset&quality=85&imagetools';
	import webp from '$lib/assets/me.jpg?w=200;400;800&webp&srcset&quality=85&imagetools';
	import fallback from '$lib/assets/me.jpg';
</script>

<div class="pic">
	<picture>
		<source srcset={avif} type="image/avif" />
		<source srcset={webp} type="image/webp" />
		<img class="me" src={fallback} height="800" width="800" alt="Moi"/>
	</picture>
</div>

<style lang="postcss">
	.pic {
		@apply w-80 mx-auto rounded-full ring-4 hover:ring-8
		hover:ring-secondary hover:scale-105 active:ring-success active:scale-95
		transition-all ring-primary ring-offset-base-100 ring-offset-2;
	}
	.me {
		@apply m-0;
	}
</style>
