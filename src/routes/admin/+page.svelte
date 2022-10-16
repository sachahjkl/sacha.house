<script lang="ts">
	import { PUBLIC_PROXYCURL_API_ENDPOINT } from '$env/static/public';
	import PrismJs from '$lib/components/PrismJS.svelte';
	import { countAPIConfig, MOI, SITE_TITLE } from '$lib/constants';
	import { toast } from '@zerodevx/svelte-toast';
	import type { Result } from 'countapi-js';
	import { onMount } from 'svelte';
	import type { UpdateProfileData } from '../api/linkedinProfile/+server';
	import type { PageData } from './$types';

	export let data: PageData;
	let creditBalance = -1;
	let visites = data.visites;

	let profile = {};

	let loadingProfile = true;
	let loadingCredits = true;
	let promiseCountApi = Promise.resolve();

	const toastCredits = (credits: number) => `
	<strong>👍 Profil mis à jour !</strong><br>
	Il te reste ${credits} crédit(s)`;

	const updateProfile = async () => {
		loadingProfile = true;
		loadingCredits = true;
		try {
			const res = await fetch('/api/linkedinProfile', { method: 'PATCH' });
			if (!res.ok) throw new Error();

			const data: UpdateProfileData = await res.json();
			creditBalance = creditBalance - 1;
			profile = data.profile as {};

			toast.push(toastCredits(creditBalance));
		} catch (error) {
			toast.push('Echec de la mise à jour du profil.');
		} finally {
			loadingProfile = false;
			loadingCredits = false;
		}
	};

	const updateCounter = async (amount: number) => {
		const { key, namespace } = countAPIConfig;
		const promiseCountApi = await fetch(
			`https://api.countapi.xyz/update/${namespace}/${key}?amount=${amount}`
		);
		visites = ((await promiseCountApi.json()) as Result).value;
	};

	onMount(async () => {
		creditBalance = parseInt(await fetch('/api/admin/creditBalance').then((res) => res.text()));
		profile = await fetch('/api/linkedinProfile').then(
			async (res) => (await res.json()) as Record<string, unknown>
		);
		loadingProfile = false;
		loadingCredits = false;
	});
</script>

<svelte:head>
	<title>admin / {SITE_TITLE}</title>
</svelte:head>

<article class="prose">
	<h1>admin</h1>

	<section>
		<h2>Adresse IP</h2>

		<p>
			L'IP actuelle avec laquelle tu accèdes au panneau d'admin est <code
				class="bg-base-content text-base-100 p-1 px-2 rounded">{data.ip}</code
			>
		</p>
	</section>
	<div class="divider" />
	<section>
		<h2>Données du profil LinkedIn</h2>
		<p>
			Les données pour le profil LinkedIn proviennent de l'API <a
				href={PUBLIC_PROXYCURL_API_ENDPOINT}>{PUBLIC_PROXYCURL_API_ENDPOINT}</a
			>.
		</p>
		<p>
			{#if loadingCredits}
				<span class="animate-spin inline-block">⚙️</span> Chargement du crédit...
			{:else}
				Il reste <b>{creditBalance} crédits</b> pour raffraichir ces données.
			{/if}
		</p>
		<button
			class="refresh-linkedin btn btn-sm gap-2"
			on:keypress={updateProfile}
			on:click={updateProfile}
		>
			<div class="refresh-icon">⚙️</div>
			Rafraichir le profil (coûte 1 crédit)
		</button>
		{#if loadingProfile}
			<p>
				<span class="animate-spin inline-block">⚙️</span> Chargement des données...
			</p>
		{:else}
			<PrismJs code={JSON.stringify(profile, null, 1)} language="javascript" />
		{/if}
	</section>
	<section>
		<h2>Nombre de visites</h2>

		{#await promiseCountApi}
			<p>
				<span class="animate-spin inline-block">⚙️</span> Chargement des données...
			</p>
		{:then _}
			<p>Nous avons reçu un total de <b> {visites} visites</b>.</p>
			<button class="btn gap-2" on:click={() => updateCounter(1)}>
				<div class="action-icon text-xl">+</div>
				Incrémenter</button
			>
		{/await}
	</section>
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

	button:hover .action-icon {
		@apply transition-all;
		animation: bounce 1s infinite;
	}
</style>
