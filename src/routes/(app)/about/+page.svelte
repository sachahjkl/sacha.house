<script lang="ts">
	import Avatar from '$lib/components/Avatar.svelte';
	import CopyableValue from '$lib/components/CopyableValue.svelte';
	import Education from '$lib/components/Education.svelte';
	import Experience from '$lib/components/Experience.svelte';
	import { MOI, PRETTY_NOM, PRETTY_PRENOM } from '$lib/me';
	import type { PageData } from '../$types';

	interface Props {
		data: PageData;
	}

	let { data }: Props = $props();
</script>

<article class="prose max-w-full">
	<h1 class="h1">about</h1>
	<section>
		<div class="avatar block mx-auto">
			<Avatar />
		</div>

		<p>
			My name is <b>{PRETTY_PRENOM} {PRETTY_NOM}</b>, I'm
			<em>{new Date().getFullYear() - MOI.dateNaissance.getFullYear()} years old</em>
			and I live in <em>{MOI.placeOfLiving}</em>.
		</p>
		<p>I'm a software engineer. I strive to produce simple, high-quality work.</p>

		<p>
			Feel free to <a href="mailto:{MOI.mail}">send me an email</a> about what you think of this site
			or any other topic that might interest me (work, discussion, project, ...).
		</p>
		<p>
			You can <b>find my resume</b> by clicking
			<a href={MOI.curriculumVitae.toString()}>here</a>.
		</p>
	</section>
	<div class="divider"></div>
	<section>
		<h2 id="professional-details">🖥️ Professional Details</h2>
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
		<h2 id="academic-background">🏫 Academic Background</h2>
		<hr class="mb-0" />
		{#await data.streaming.profile}
			<p>Loading ...</p>
		{:then profile}
			{#each profile.education as edu, i (i)}
				<Education education={edu} />
			{/each}
		{/await}
	</section>
	<div class="divider"></div>
	<section>
		<h2>🖋️ Contact</h2>
		<p>Here's a list of my contact information:</p>
		<ul>
			<li>Email: <CopyableValue value={MOI.mail} /></li>
			<li>Ethereum Address: <CopyableValue value={MOI.ethAddress} /></li>
			<li>
				Monero Address: <CopyableValue value={MOI.moneroAdress} />
			</li>
			<li>
				LinkedIn Profile: <a href={MOI.linkedin.toString()}>{MOI.linkedin.toString()}</a>
			</li>
			<li>
				GitHub Profile: <a href={MOI.github.toString()}>{MOI.github.toString()}</a>
			</li>
			<li>
				GitLab Profile: <a href={MOI.gitlab.toString()}>{MOI.gitlab.toString()}</a>
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
