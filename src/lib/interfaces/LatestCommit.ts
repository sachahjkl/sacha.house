export interface LatestCommit {
	project: {
		repository: {
			rootRef: string;
			paginatedTree: {
				nodes: Array<{
					lastCommit: {
						sha: string;
					};
				}>;
			};
		};
	};
}
