<script lang="ts">
	import type { Experience } from '$lib/interfaces/LinkedinProfile';

	interface Props {
		experience: Experience;
	}

	let { experience }: Props = $props();
	const titre = experience.title;
	const compétences: string[] = [];
	const { description } = experience;
	const lieu = { name: experience.company, website: experience?.company_linkedin_profile_url };
	const startDate = new Date(
		experience.starts_at.year,
		experience.starts_at.month - 1,
		experience.starts_at.day
	);
	const endDate = experience.ends_at
		? new Date(experience.ends_at.year, experience.ends_at.month - 1, experience.ends_at.day)
		: null;
</script>

<section>
	<h3 class="mb-0 font-bold text-opacity-50">
		{#if lieu.website}
			<a class="no-underline hover:underline font-bold" href={lieu.website}>{lieu.name} 🔗</a>
		{:else}
			{lieu.name}
		{/if}
		<!-- <small class="ml-1  text-opacity-70 not-prose"
			>à

		</small> -->
	</h3>
	<h4 class="italic font-normal">
		{titre}
	</h4>
	<small class=" text-opacity-50">
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
		{#each compétences as compétence}
			<div class="badge badge-primary">{compétence}</div>
		{/each}
	</div>
	<p>{description}</p>
</section>
