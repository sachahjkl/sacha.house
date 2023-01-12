<script lang="ts">
	import type { Education } from '$lib/interfaces/LinkedinProfile';

	export let education: Education;
	const titre = `${education.degree_name} en ${education.field_of_study}`;
	const lieu = { name: education.school, website: education?.school_linkedin_profile_url };
	const startDate = new Date(
		education.starts_at.year,
		education.starts_at.month - 1,
		education.starts_at.day
	);
	const endDate = education.ends_at
		? new Date(education.ends_at.year, education.ends_at.month - 1, education.ends_at.day)
		: null;
	const { description } = education;
</script>

<section>
	<h3 class="mb-0 font-bold">
		{titre}
	</h3>
	<h4 class="italic font-normal">
		{#if lieu.website}
			<a class="no-underline hover:underline text-base-content text-opacity-70" href={lieu.website}
				>{lieu.name} 🔗</a
			>
		{:else}
			{lieu.name}
		{/if}
	</h4>
	<small class="text-base-content text-opacity-50">
		<time>
			{startDate.toLocaleDateString('fr-FR', {
				year: 'numeric',
				month: 'short'
			})}
		</time>
		{#if endDate}
			-
			<time>
				{endDate.toLocaleDateString('fr-FR', {
					year: 'numeric',
					month: 'short'
				})}
			</time>
		{/if}
	</small>
	<div>
		<!-- {#each compétences as compétence}
			<div class="badge badge-primary">{compétence}</div>
		{/each} -->
	</div>
	{#if description}
		<p>{description}</p>
	{/if}
</section>
