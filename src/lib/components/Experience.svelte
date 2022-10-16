<script lang="ts">
	import type { Experience } from '$lib/interfaces/LinkedinProfile';

	export let experience: Experience;
	const titre = experience.title;
	const compétences: string[] = [];
	const {description} = experience;
	const lieu = { name: experience.company, website: experience?.company_linkedin_profile_url };
	const startDate = new Date(experience.starts_at.year, experience.starts_at.month - 1, experience.starts_at.day);
	const endDate = experience.ends_at
		? new Date(experience.ends_at.year, experience.ends_at.month - 1, experience.ends_at.day)
		: null;
</script>

<section>
	<h3>
		{titre}
		<small class="ml-1 text-base-content text-opacity-70 not-prose"
			>à
			{#if lieu.website}
				<a class="underline" href={lieu.website}>{lieu.name}</a>
			{:else}
				{lieu.name}
			{/if}
		</small>
	</h3>
	<small class="text-base-content text-opacity-50">
		{startDate.toLocaleDateString('fr-FR', {
			year: 'numeric',
			month: 'short'
		})}
		{#if endDate}
			-
			{endDate.toLocaleDateString('fr-FR', {
				year: 'numeric',
				month: 'short'
			})}
		{/if}
	</small>
	<div>
		{#each compétences as compétence}
			<div class="badge badge-primary">{compétence}</div>
		{/each}
	</div>
	<p>{description}</p>
</section>
