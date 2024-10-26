<script lang="ts">
	import githubSrc from '$lib/assets/github.png';
	import gitlabSrc from '$lib/assets/gitlab.png';
	import Project from '$lib/components/Project.svelte';
	import { MOI } from '$lib/me';
	import type { PageData } from '../$types';

	interface Props {
		data: PageData;
	}

	let { data }: Props = $props();
</script>

<article>
	<h1 class="h1">projects</h1>
	<p>
		A collection of my work, including both completed and ongoing projects. These repositories were
		created to:
	</p>
	<ul class="ms-4 list-inside list-[square]">
		<li>Explore new technologies</li>
		<li>Practice project management, design, and software architecture</li>
		<li>
			Collaborate on personal projects (<a href={MOI.links.hayekfr.toString()}> website example </a>
			and its <a href={MOI.links.hayekfrRepo.toString()}>repository</a>, task automation, etc.)
		</li>
		<li>Organize academic work</li>
		<li>
			Store personal environment files (e.g., <a href={MOI.links.dotfiles.toString()}>dotfiles</a>)
		</li>
	</ul>
	<p>
		Most of my work is hosted on <b>GitLab</b>, with some minor projects on <b>GitHub</b>.
	</p>
	<div class="divider"></div>
	<section>
		<h2 class="h2">
			<img class="title-logo" width="15" src={gitlabSrc} alt="GitLab Logo" /> GitLab /
			<a href={MOI.gitlab.toString()}>@{MOI.gitlab.pathname.split('/').pop()}</a>
		</h2>
		{#await data.streaming.projects}
			<p>Loading projects...</p>
		{:then projects}
			<ul class="projects">
				{#each projects.gitlab as { avatarUrl, description, descriptionHtml, name, url, group }}
					<li class="project">
						<Project
							{description}
							{descriptionHtml}
							name={`${name} ${group ? `(${group?.name})` : ''}`}
							{url}
							{avatarUrl}
						/>
					</li>
				{:else}
					<li>No projects available.</li>
				{/each}
			</ul>
		{/await}
	</section>
	<section>
		<h2 class="h2 mb-0">
			<img class="title-logo" src={githubSrc} alt="GitHub Logo" /> GitHub /
			<a href={MOI.github.toString()}>@{MOI.github.pathname.split('/').pop()}</a>
		</h2>
		{#await data.streaming.projects}
			<p>Loading projects...</p>
		{:then projects}
			<ul class="projects">
				{#each projects.github as { description, name, url }}
					<li class="project">
						<Project {description} {name} {url} />
					</li>
				{:else}
					<li>No projects available.</li>
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
		@apply m-0 mr-2 inline-block w-[1.2em] align-middle;
	}

	.projects {
		@apply mx-4 flex max-h-[540px] snap-y snap-mandatory list-none flex-col gap-4 overflow-y-scroll border-y-2 border-textColor p-0;
		scrollbar-width: thin;
	}
	.project {
		@apply snap-start;
	}
</style>
