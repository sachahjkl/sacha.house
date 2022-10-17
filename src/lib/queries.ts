import { gql } from 'graphql-request';

export const GET_PROJECTS_GITLAB = gql`
	query GET_PROJECTS_GITLAB {
		projects(membership: true) {
			nodes {
				...ProjectView
			}
		}
	}
	fragment ProjectView on Project {
		name
		url: webUrl
		avatarUrl
		description: descriptionHtml
		visibility
	}
`;

export const GET_PROJECTS_GITHUB = gql`
	query GET_PROJECTS_GITHUB($username: String!) {
		user(login: $username) {
			projects: repositories(first: 50) {
				nodes {
					name
					url
					description
					visibility
				}
			}
		}
	}
`;

export const GET_LATEST_COMMIT = gql`
	query GET_LATEST_COMMIT($repoID: ID!) {
		project(fullPath: $repoID) {
			repository {
				rootRef
				paginatedTree {
					nodes {
						lastCommit {
							sha
						}
					}
				}
			}
		}
	}
`;

export const GET_POSTS = gql`
	query GET_POSTS {
		posts(orderBy: publishedAt_ASC, stage: PUBLISHED) {
			slug
			title
			updatedAt
			publishedAt
			content {
				html
			}
		}
	}
`;

export const GET_POST = gql`
	query GET_POST($slug: String = "") {
		post(where: { slug: $slug }) {
			slug
			title
			updatedAt
			createdAt
			content {
				html
				text
			}
		}
	}
`;
