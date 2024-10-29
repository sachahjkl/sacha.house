<script lang="ts">
	import Avatar from '$lib/components/Avatar.svelte';
	import CopyableValue from '$lib/components/CopyableValue.svelte';
	import Education from '$lib/components/Education.svelte';
	import Experience from '$lib/components/Experience.svelte';
	import { MOI, PRETTY_NOM, PRETTY_PRENOM } from '$lib/me';
	import type { PageData } from './$types';
	import type { LinkedinProfile } from '$lib/interfaces/LinkedinProfile';
	import { isError as isKitError } from '$lib/utils';

	interface Props {
		data: PageData;
	}

	let { data }: Props = $props();

	let maybeProfile = $derived.by<Promise<LinkedinProfile>>(async () => {
		let res = await data.profile;
		if (isKitError(res)) {
			return Promise.reject(res.message);
		}
		return res;
	});
</script>

<article class="max-w-full text-sm sm:text-base">
	<h1 class="h1">about</h1>
	<section class="mb-8">
		<div class="avatar my-6 flex justify-center">
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

	<section class="mb-8">
		<h2 id="professional-details" class="h2">🖥️ Professional Details</h2>
		<div class="flex flex-col gap-4">
			{#await maybeProfile}
				<p>Loading ...</p>
			{:then profile}
				{#each profile.experiences as experience, i (i)}
					<Experience {experience} />
				{/each}
			{:catch error}
				<p>{error}</p>
			{/await}
		</div>
	</section>
	<section class="mb-8">
		<h2 id="academic-background" class="h2">🏫 Academic Background</h2>
		<div class="flex flex-col gap-4">
			{#await maybeProfile}
				<p>Loading ...</p>
			{:then profile}
				{#each profile.education as edu, i (i)}
					<Education education={edu} />
				{/each}
			{:catch error}
				<p>{error}</p>
			{/await}
		</div>
	</section>
	<section>
		<h2 id="contact" class="h2">🖋️ Contact</h2>
		<p>Here's a list of my contact information:</p>
		<ul class="list-inside list-[square] break-words">
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
		@apply underline;
	}

	p {
		@apply mb-4;
	}
</style>
