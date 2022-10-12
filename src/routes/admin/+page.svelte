<script lang="ts">
	import { PUBLIC_PROXYCURL_API_ENDPOINT } from '$env/static/public';
	import PrismJs from '$lib/components/PrismJS.svelte';
	import { countAPIConfig, MOI } from '$lib/constants';
	import { toast } from '@zerodevx/svelte-toast';
	import type { Result } from 'countapi-js';
	import { onMount } from 'svelte';
	import { writable } from 'svelte/store';
	import type { PageData } from './$types';

	export let data: PageData;
	const creditBalance = writable(-1);
	const visites = writable(data.visites);

	let refreshingLinkedinStuff = true;
	let promiseCountApi = Promise.resolve();

	const toastCredits = (credits: number) => `
	<strong>👍 Profil mis à jour !</strong><br>
	Il te reste ${credits} crédit(s)`;

	const refreshCredit = async () => {
		refreshingLinkedinStuff = true;
		const res = await fetch('/api/admin/creditBalance');
		$creditBalance = parseInt(await res.text());
		refreshingLinkedinStuff = false;
		return $creditBalance;
	};

	const updateProfile = async () => {
		try {
			// Ici, procéder à la MAJ du profil linkedin.

			toast.push(toastCredits(await refreshCredit()));
		} catch (error) {
			toast.push('Echec de la mise à jour du profil.');
		}
	};

	const updateCounter = async (amount: number) => {
		const { key, namespace } = countAPIConfig;
		const promiseCountApi = await fetch(
			`https://api.countapi.xyz/update/${namespace}/${key}?amount=${amount}`
		);
		$visites = ((await promiseCountApi.json()) as Result).value;
	};

	onMount(() => ($creditBalance === -1 ? refreshCredit() : null));
</script>

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
			{#if refreshingLinkedinStuff}
				<span class="animate-spin inline-block">⚙️</span> Chargement du crédit...
			{:else}
				Il reste <b>{$creditBalance} crédits</b> pour raffraichir ces données.
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
		{#if refreshingLinkedinStuff}
			<p>
				<span class="animate-spin inline-block">⚙️</span> Chargement des données...
			</p>
		{:else}
			<PrismJs code={JSON.stringify(MOI.linkedinProfile, null, 1)} language="javascript" />
		{/if}
	</section>
	<section>
		<h2>Nombre de visites</h2>

		{#await promiseCountApi}
			<p>
				<span class="animate-spin inline-block">⚙️</span> Chargement des données...
			</p>
		{:then _}
			<p>Nous avons reçu un total de <b> {$visites} visites</b>.</p>
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
