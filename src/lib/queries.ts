function gql(strings: TemplateStringsArray) {
	return strings.join(' ');
}

export function makeGqlBody(query: string, variables: Record<string, string>) {
	return JSON.stringify({
		query,
		variables
	});
}

export const GET_PROJECTS_GITLAB = gql`
	query GET_PROJECTS_GITLAB($username: String!) {
		user(username: $username) {
			username
			groups {
				nodes {
					name
					projects {
						nodes {
							...ProjectView
						}
					}
				}
			}
			projectMemberships {
				nodes {
					project {
						...ProjectView
					}
				}
			}
		}
	}

	fragment ProjectView on Project {
		name
		url: webUrl
		avatarUrl
		description
	}
`;

export const GET_PROJECTS_GITHUB = gql`
	query GET_PROJECTS_GITHUB($username: String!) {
		user(login: $username) {
			username: login
			projects: repositories(first: 50) {
				nodes {
					name
					url
					description
				}
			}
		}
	}
`;
