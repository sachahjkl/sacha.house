<script lang="ts">
	import { MOI, SITE_TITLE } from '$lib/constants';
	import gitlabSrc from '$lib/assets/gitlab.png';
	import githubSrc from '$lib/assets/github.png';
	import type { Data, Groups, ProjectMemberships } from '$lib/interfaces/Project';
	import Project from '$lib/components/Project.svelte';

	const getProjects = async () => {
		const res = await fetch('/projets', {
			headers: {
				'Content-Type': 'application/json'
			}
		});
		const data: Data = await res.json();
		return data;
	};

	const gitlabMerge = (groups: Groups, projectMemberships: ProjectMemberships) => {
		groups.nodes.map((node) => {
			return node.projects.nodes;
		});
	};

	const projectsPromise = getProjects();
</script>

<svelte:head>
	<title>projets / {SITE_TITLE}</title>
</svelte:head>
<article class="prose">
	<h1 class="">Projets</h1>
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
		{#await projectsPromise}
			<button class="btn btn-ghost loading">Chargement des données...</button>
		{:then data}
			<ul class="projects not-prose">
				{#each data.gitlab.user.groups.nodes as group}
					{#each group.projects.nodes.sort((a, b) => (b.description?.length ?? 0) - (a.description?.length ?? 0)) as { avatarUrl, description, name, url }}
						<li>
							<Project {description} name={`${name} (groupe ${group.name})`} {url} {avatarUrl} />
						</li>
					{/each}
				{:else}
					<li>Pas de projet !</li>
				{/each}
				{#each data.gitlab.user.projectMemberships.nodes.sort((a, b) => (b.project.description?.length ?? 0) - (a.project.description?.length ?? 0)) as { project }}
					<li>
						<Project
							description={project.description}
							name={project.name}
							url={project.url}
							avatarUrl={project.avatarUrl}
						/>
					</li>
				{/each}
			</ul>
		{/await}
		<!--  -->
	</section>
	<div class="divider" />
	<section>
		<h2>
			<img class="title-logo" src={githubSrc} alt="GitHub Logo" /> GitHub /
			<a href={MOI.github.toString()}>@{MOI.github.pathname.split('/').pop()}</a>
		</h2>
		{#await projectsPromise}
			<button class="btn btn-ghost loading">Chargement des données...</button>
		{:then data}
			<ul class="projects not-prose">
				{#each data.github.user.projects.nodes.sort((a, b) => (b.description?.length ?? 0) - (a.description?.length ?? 0)) as { description, name, url }}
					<li>
						<Project {description} {name} {url} />
					</li>
				{:else}²
					<li>Pas de projet !</li>
				{/each}
			</ul>
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
		@apply list-none max-h-[500px] overflow-y-scroll;
	}
</style>
