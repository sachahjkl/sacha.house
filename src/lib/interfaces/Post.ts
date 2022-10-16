export interface Post {
	slug: string;
	title: string;
	updatedAt: string;
	createdAt: string;
	content: {
		html: string;
	};
}
