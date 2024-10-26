<script lang="ts">
	import Avatar from '$lib/components/Avatar.svelte';
	import CopyableValue from '$lib/components/CopyableValue.svelte';
	import Education from '$lib/components/Education.svelte';
	import Experience from '$lib/components/Experience.svelte';
	import { MOI, PRETTY_NOM, PRETTY_PRENOM } from '$lib/me';

	export let data;
</script>

<article class="prose max-w-full">
	<h1 class="h1">about</h1>
	<section>
		<div class="avatar block mx-auto">
			<Avatar />
		</div>

		<p>
			Je m'appelle <b>{PRETTY_PRENOM} {PRETTY_NOM}</b>, j'ai
			<em>{new Date().getFullYear() - MOI.dateNaissance.getFullYear()} ans</em>
			j'habite à <em>{MOI.placeOfLiving}</em>.
		</p>
		<p>Je suis ingénieur en informatique. J'aspire à produire du travail simple et de qualité</p>

		<p>
			N’hésitez pas à <a href="mailto:{MOI.mail}">m’envoyer un mail</a> à propos de ce que vous pensez
			de ce site ou tout autre sujet qui pourrait m’intéresser (travail, discussion, projet, ...).
		</p>
		<p>
			Vous pouvez <b>retrouver mon CV</b> en cliquant
			<a href={MOI.curriculumVitae.toString()}>ici</a>.
		</p>
	</section>
	<div class="divider" />
	<section>
		<h2 id="détails-professionnels">🖥️ Détails professionels</h2>
		<hr class="mb-0" />
		{#await data.streaming.profile}
			<p>Loading ...</p>
		{:then profile}
			{#each profile.experiences as experience, i (i)}
				<Experience {experience} />
			{/each}
		{/await}
	</section>
	<section>
		<h2 id="parcours-académique">🏫 Parcours académique</h2>
		<hr class="mb-0" />
		{#await data.streaming.profile}
			<p>Loading ...</p>
		{:then profile}
			{#each profile.education as edu, i (i)}
				<Education education={edu} />
			{/each}
		{/await}
	</section>
	<div class="divider" />
	<section>
		<h2>🖋️ Contact</h2>
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
	article {
		@apply mx-auto print:max-w-full;
	}
	a {
		@apply hover:scale-105 transition-all;
	}
</style>
