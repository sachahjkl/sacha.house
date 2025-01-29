<script lang="ts">
	import githubSrc from '$lib/assets/github.png';
	import gitlabSrc from '$lib/assets/gitlab.png';
	import Project from '$lib/components/Project.svelte';
	import { MOI } from '$lib/me';
	import type { PageData } from './$types';

	interface Props {
		data: PageData;
	}

	let { data }: Props = $props();
</script>

<article class="mx-auto">
	<h1 class="h1">projects</h1>
	<section class="mb-8">
		<p>
			A collection of my work, including both completed and ongoing projects. These repositories
			were created to:
		</p>
		<ul class="ms-4 list-inside list-[square]">
			<li>Explore new technologies</li>
			<li>Practice project management, design, and software architecture</li>
			<li>
				Collaborate on personal projects (<a href={MOI.links.hayekfr.toString()}>
					website example
				</a>
				and its <a href={MOI.links.hayekfrRepo.toString()}>repository</a>, task automation, etc.)
			</li>
			<li>Organize academic work</li>
			<li>
				Store personal environment files (e.g., <a href={MOI.links.dotfiles.toString()}>dotfiles</a
				>)
			</li>
		</ul>
		<p>
			Most of my work is hosted on <b>GitLab</b>, with some minor projects on <b>GitHub</b>.
		</p>
	</section>
	<div class="divider"></div>
	<section class="mb-8">
		<h2 class="h2">
			<img
				class="m-0 mr-2 inline-block w-[1.2em] align-middle"
				width="15"
				src={gitlabSrc}
				alt="GitLab Logo"
			/>
			GitLab /
			<a href={MOI.gitlab.toString()}>@{MOI.gitlab.pathname.split('/').pop()}</a>
		</h2>
		{#await data.projects}
			<p>Loading projects...</p>
		{:then projects}
			<ul
				class="scrollbar-thin border-textColor mx-4 flex max-h-[540px] snap-y snap-mandatory list-none flex-col gap-4 overflow-y-scroll border-y-4 p-0"
			>
				{#each projects.gitlab as { avatarUrl, description, descriptionHtml, name, url, group }}
					<li class="snap-start">
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
	<section class="mb-8">
		<h2 class="h2 mb-0">
			<img class="m-0 mr-2 inline-block w-[1.2em] align-middle" src={githubSrc} alt="GitHub Logo" />
			GitHub /
			<a href={MOI.github.toString()}>@{MOI.github.pathname.split('/').pop()}</a>
		</h2>
		{#await data.projects}
			<p>Loading projects...</p>
		{:then projects}
			<ul
				class="scrollbar-thin border-textColor mx-4 flex max-h-[540px] snap-y snap-mandatory list-none flex-col gap-4 overflow-y-scroll border-y-4 p-0"
			>
				{#each projects.github as { description, name, url }}
					<li class="snap-start">
						<Project {description} {name} {url} />
					</li>
				{:else}
					<li>No projects available.</li>
				{/each}
			</ul>
		{/await}
	</section>
</article>
