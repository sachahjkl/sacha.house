<script lang="ts">
	import { fade, fly } from 'svelte/transition';

	interface Props {
		imgSrc?: string;
		children?: import('svelte').Snippet;
	}

	let { imgSrc = '/me.jpg', children }: Props = $props();
</script>

<div in:fade class="avatarTitle">
	<div in:fly={{ x: -50 }} class="avatar">
		<div class="w-[2em] rounded-full ring ring-primary ring-offset-2">
			<img src={imgSrc} alt="title" />
		</div>
	</div>
	<span in:fly={{ x: 50 }} class="title">{#if children}{@render children()}{:else}My Title{/if}</span>
</div>

<style lang="postcss">
	.avatarTitle {
		@apply flex items-center;
	}

	.avatar {
		@apply mx-2 hover:scale-95 active:scale-105 transition-transform;
	}

	img {
		@apply m-0;
	}

	.title {
		@apply ml-3;
	}
</style>
