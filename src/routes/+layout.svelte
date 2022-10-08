<script lang="ts">
	import { SITE_TITLE } from '$lib/constants';
</script>

<svelte:head>
	<title>Accueil / {SITE_TITLE}</title>
</svelte:head>

<slot><!-- optional fallback --></slot>
