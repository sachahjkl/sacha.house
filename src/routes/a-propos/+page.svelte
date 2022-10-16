<script lang="ts">
	import { MOI, SITE_TITLE } from '$lib/constants';
	import { capitalize } from '$lib/utils';

	import picSrc from '$lib/assets/me.jpg';
	import CopyableValue from '$lib/components/CopyableValue.svelte';
	import { onMount } from 'svelte';
	import type { LinkedinProfile } from '$lib/interfaces/LinkedinProfile';
	import Experience from '$lib/components/Experience.svelte';
	import Education from '$lib/components/Education.svelte';

	let profile: LinkedinProfile;
	let loadingProfile = true;

	onMount(async () => {
		profile = await fetch('/api/linkedinProfile').then(async (res) => await res.json());
		loadingProfile = false;
	});
</script>

<svelte:head>
	<title>à propos / {SITE_TITLE}</title>
</svelte:head>

<article class="prose">
	<h1 class="">à propos</h1>
	<section>
		<div class="avatar block mx-auto">
			<div class="pic">
				<img class="me" src={picSrc} alt="Moi" />
			</div>
		</div>

		<p>
			Je m'appelle <b>{capitalize(MOI.prenom)} {capitalize(MOI.nom)}</b>, j'ai
			<em>{new Date().getFullYear() - MOI.dateNaissance.getFullYear()} ans</em>
			j'habite à <em>{MOI.placeOfLiving}</em>.
		</p>
		<p>Je suis ingénieur en informatique. J'aspire à produire du travail simple et de qualité</p>

		<p>
			N’hésitez pas à <a href="mailto:{MOI.mail}">m’envoyer un mail</a> à propos de ce que vous pensez
			de ce site ou tout autre sujet qui pourrait m’intéresser (travail, discussion, projet, ...).
		</p>
		<p>
			Vous pouvez retrouver mon CV en cliquant <a href={MOI.curriculumVitae.toString()}>ici</a>.
		</p>
	</section>
	<div class="divider" />
	<section>
		<h2 id="détails-professionnels">Détails professionels</h2>
		{#if loadingProfile}
			<span class="animate-spin inline-block">⚙️</span> Chargement du profil...
		{:else}
			<ul class="steps steps-vertical p-0">
				{#each profile.experiences as experience}
					<li data-content="●" class="step ">
						<div class="text-left place self-start">
							<Experience {experience} />
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
	<div class="divider" />
	<section>
		<h2 id="parcours-académique">Parcours académique</h2>
		{#if loadingProfile}
			<span class="animate-spin inline-block">⚙️</span> Chargement du profil...
		{:else}
			<ul class="steps steps-vertical p-0">
				{#each profile.education as edu}
					<li data-content="●" class="step ">
						<div class="text-left place self-start">
							<Education education={edu} />
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
	<div class="divider" />
	<section>
		<h2>Contact</h2>
		<p>Voici, en vrac, une liste d'information de contact me concernant :</p>
		<ul>
			<li>Mail : <CopyableValue value={MOI.mail} /></li>
			<li>Adresse Ethereum : <CopyableValue value={MOI.ethAddress} /></li>
			<li>
				Adresse Monero : <CopyableValue value={MOI.moneroAdress} />
			</li>
			<li>
				Profil LinkedIn : <a href={MOI.linkedin.toString()}>{MOI.linkedin.toString()}</a>
			</li>
			<li>
				Profil GitHub : <a href={MOI.github.toString()}>{MOI.github.toString()}</a>
			</li>
			<li>
				Profil GitLab : <a href={MOI.gitlab.toString()}>{MOI.gitlab.toString()}</a>
			</li>
		</ul>
	</section>
</article>

<style lang="postcss">
	.pic {
		@apply w-80 mx-auto rounded-full ring-4 hover:ring-8
		hover:ring-secondary hover:scale-105 active:ring-success active:scale-95
		transition-all ring-primary ring-offset-base-100 ring-offset-2;
	}
	article {
		@apply mx-auto;
	}
	.me {
		@apply m-0;
	}
	a {
		@apply hover:scale-105 transition-all;
	}
	.step::after {
		@apply self-start mt-8;
	}

	.step::before {
		@apply -translate-y-[85%];
	}
</style>
