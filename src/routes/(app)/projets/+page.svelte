<script lang="ts">
	import githubSrc from '$lib/assets/github.png';
	import gitlabSrc from '$lib/assets/gitlab.png';
	import Project from '$lib/components/Project.svelte';
	import { MOI } from '$lib/me';

	export let data;
</script>

<article class="prose">
	<h1 class="">projets</h1>
	<p>Mes projets, plus ou moins aboutis. Dans la globalité, l'objectif de ces dépôts était :</p>
	<ul>
		<li>D'apprendre des nouvelles technologies.</li>
		<li>
			Pratiquer des méthodologies de gestion/conception/architecture d'un projet informatique.
		</li>
		<li>
			Aider un ami à réaliser son projet personnel (<a href={MOI.links.hayekfr.toString()}>
				site web
			</a>
			& <a href={MOI.links.hayekfrRepo.toString()}>📦 dépôt</a>, automatiser une tâche, ...)
		</li>
		<li>Organiser mes travaux d'étudiant à rendre.</li>
		<li>
			Conserver des fichiers d'environnements personnels (eg.
			<a href={MOI.links.dotfiles.toString()}> mes dotfiles </a> )
		</li>
	</ul>
	<p>
		J'héberge l'essentiel de mon travail sur <b>GitLab</b>. Cependant, certains projets mineurs se
		trouvent sur <b>GitHub</b>.
	</p>
	<div class="divider" />
	<section>
		<h2>
			<img class="title-logo" src={gitlabSrc} alt="GitLab Logo" /> GitLab /
			<a href={MOI.gitlab.toString()}>@{MOI.gitlab.pathname.split('/').pop()}</a>
		</h2>
		{#await data.streaming.projects}
			<p>Loading ...</p>
		{:then projects}
			<ul class="projects not-prose">
				{#each projects.gitlab as { avatarUrl, description, descriptionHtml, name, url, group }}
					<li class="project">
						<Project
							{description}
							{descriptionHtml}
							name={`${name} ${group ? `(groupe ${group?.name})` : ''}`}
							{url}
							{avatarUrl}
						/>
					</li>
				{:else}
					<li>Pas de projet !</li>
				{/each}
			</ul>
		{/await}
	</section>
	<section>
		<h2>
			<img class="title-logo" src={githubSrc} alt="GitHub Logo" /> GitHub /
			<a href={MOI.github.toString()}>@{MOI.github.pathname.split('/').pop()}</a>
		</h2>
		{#await data.streaming.projects}
			<p>Loading ...</p>
		{:then projects}
			<ul class="projects not-prose">
				{#each projects.github as { description, name, url }}
					<li class="project">
						<Project {description} {name} {url} />
					</li>
				{:else}
					<li>Pas de projet !</li>
				{/each}
			</ul>
			<!-- promise was fulfilled -->
		{/await}
	</section>
</article>

<style lang="postcss">
	article {
		@apply mx-auto;
	}

	img.title-logo {
		@apply w-[2em] inline-block align-middle m-0 mr-2;
	}

	.projects {
		@apply list-none max-h-[540px] p-0 overflow-y-scroll border-y-2 border-base-content border-opacity-10
		snap-y snap-mandatory;
	}
	.project {
		@apply snap-start first-of-type:pt-1 last-of-type:pb-1;
	}
</style>
