<script lang="ts">
	import type { Education } from '$lib/interfaces/LinkedinProfile';

	interface Props {
		education: Education;
	}

	let { education }: Props = $props();
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

<section class="border-s-[16px] border-textColor py-2 ps-4">
	<div id="title" class="mb-3">
		<h3 class="ms-0 font-bold">
			{#if lieu.website}
				<a class="font-bold no-underline hover:underline" href={lieu.website}>{lieu.name} 🔗</a>
			{:else}
				{lieu.name}
			{/if}
		</h3>

		<h4 class="italic">
			{titre}
		</h4>
		<small class="text-bgOffColor">
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
	</div>

	<div>
		<!-- {#each compétences as compétence}
			<div class="badge badge-primary">{compétence}</div>
		{/each} -->
	</div>
	{#if description}
		<p>{description}</p>
	{:else}
		<p>No description available.</p>
	{/if}
</section>
