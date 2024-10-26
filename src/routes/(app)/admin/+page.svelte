<script lang="ts">
	import { enhance } from '$app/forms';
	import { env } from '$env/dynamic/public';
	import PrismJs from '$lib/components/PrismJS.svelte';

	import { toast } from '@zerodevx/svelte-toast';

	export let data;

	const toastCredits = (credits: number) => `
	<strong>👍 Profil mis à jour !</strong><br>
	Il te reste ${credits} crédit(s)`;

	const toastError = (message: string) => `
	<strong>💣 Une erreur a eu lieu</strong><br>
	${message}`;

	let profileLoading = false;

	let profileStringifiedPretty = JSON.stringify(data.profile, null, 1);
	let code: string;
	$: code = profileLoading ? 'Chargement des données du profil...' : profileStringifiedPretty;
</script>

<svelte:head>
	<meta name="robots" content="noindex nofollow" />
</svelte:head>

<article>
	<h1>admin</h1>

	<section>
		<h2>🕵️ Adresse IP</h2>

		<p>
			L'IP actuelle avec laquelle tu accèdes au panneau d'admin est <code
				class=" p-1 px-2 rounded">{data.ip}</code
			>
		</p>
	</section>
	<div class="divider" />
	<section>
		<h2>👔 Données du profil LinkedIn</h2>
		<p>
			Les données pour le profil LinkedIn proviennent de l'API <a
				href={env.PUBLIC_PROXYCURL_API_ENDPOINT}>{env.PUBLIC_PROXYCURL_API_ENDPOINT}</a
			>.
		</p>
		{#if profileLoading}
			<span class="animate-spin inline-block">⚙️</span> Chargement des données de crédits...
		{:else}
			<p>
				Il reste <b>{data.creditBalance} crédits</b> pour raffraichir ces données.
			</p>
		{/if}
		<form
			method="POST"
			action="?/updateLinkedinProfile"
			use:enhance={() => {
				profileLoading = true;

				return async ({ result, update }) => {
					await update();
					profileLoading = false;
					if (result.type === 'success') {
						const balance = Number(result.data?.creditBalance);
						toast.push(toastCredits(balance));
						data.creditBalance = balance;
					}
					if (result.type === 'failure') {
						toast.push(toastError(`${result.data?.message}`));
					}
				};
			}}
		>
			<button type="submit" class="refresh-linkedin btn btn-sm gap-2">
				<div class="refresh-icon">⚙️</div>
				Rafraichir le profil (coûte 1 crédit)
			</button>
		</form>

		<PrismJs {code} language="javascript" />
	</section>
	<!-- <section>
		<h2>#️⃣ Nombre de visites</h2>
		<p>
			{#if visitesLoading}
				<span class="animate-spin inline-block">⚙️</span> Chargement des visites...
			{:else}
				Nous avons reçu un total de <b> {data.visites} visites</b>.
			{/if}
		</p>
		<form
			method="POST"
			action="?/incrementCounter"
			use:enhance={() => {
				visitesLoading = true;
				return async ({ update }) => {
					await update();
					visitesLoading = false;
				};
			}}
		>
			<button type="submit" class="btn gap-2">
				<div class="action-icon text-xl">+</div>
				Incrémenter
			</button>
		</form>
	</section> -->
</article>

<style lang="postcss">
	article {
		@apply mx-auto;
	}
	button:hover .refresh-icon {
		@apply animate-spin transition-all;
	}

	@keyframes bounce {
		0%,
		100% {
			transform: none;
			animation-timing-function: cubic-bezier(0, 0, 0.2, 1);
		}
		50% {
			transform: translateY(-25%);
			animation-timing-function: cubic-bezier(0.8, 0, 1, 1);
		}
	}

	/* button:hover .action-icon {
		@apply transition-all;
		animation: bounce 1s infinite;
	} */
</style>
