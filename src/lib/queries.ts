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
