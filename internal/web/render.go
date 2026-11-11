package web

type BrewMessage struct {
	Text  string
	Emoji string // name of a Noto icon in static/icons/noto
}

type TeapotPageData struct {
	PageData
	Spewage     string
	BrewMessage BrewMessage
	IsATeapot   bool
}

type LoginFormData struct {
	Error string
}

type PasskeyView struct {
	ID    string
	Label string
}

type AdminPageData struct {
	PageData
	IPAddress    string
	Error        string
	PasteEnabled bool
	// BlogConflicts counts the posts that wait for a conflict resolution.
	BlogConflicts int
}

type AdminPasteListItem struct {
	GistID        string
	Revision      string
	KeyID         string
	PasteID       string
	Title         string
	CreatedAt     string
	UpdatedAt     string
	Status        string
	CanEdit       bool
	NeedsRotation bool
}

type AdminPastesPageData struct {
	PageData
	Items     []AdminPasteListItem
	Error     string
	Notice    string
	Truncated bool
}

type PasteForm struct {
	GistID        string
	Revision      string
	Title         string
	Body          string
	KeyID         string
	FormAction    string
	IsNew         bool
	NeedsRotation bool
}

type AdminPasteEditorPageData struct {
	PageData
	Form   PasteForm
	Error  string
	Notice string
}

type AdminLoginPageData struct {
	PageData
	LoginFormData
}

type AdminBlogPostView struct {
	Slug        string
	Title       string
	Status      string
	UpdatedAt   string
	PublishedAt string
	// Conflict is set when the repository and the admin both changed the post.
	Conflict bool
}

// ConflictField compares one metadata field of the site and repository versions of a post.
type ConflictField struct {
	Name       string
	Site       string
	Repository string
}

// Differs reports whether the two versions disagree on the field.
func (field ConflictField) Differs() bool { return field.Site != field.Repository }

type AdminBlogConflictPageData struct {
	PageData
	Slug    string
	Title   string
	Error   string
	Fields  []ConflictField
	Content []DiffHunk
}

type AdminBlogPostsPageData struct {
	PageData
	Posts []AdminBlogPostView
}

type BlogPostForm struct {
	IsNew       bool
	FormAction  string
	CurrentSlug string
	Revision    string
	Title       string
	Slug        string
	Description string
	Language    string
	Status      string
	PublishedAt string
	Markdown    string
	PublicURL   string
	CreatedAt   string
	UpdatedAt   string
}

type AdminBlogPostEditorPageData struct {
	PageData
	Form        BlogPostForm
	Error       string
	PreviewHTML string
}

type AdminWebAuthnPageData struct {
	PageData
	Passkeys []PasskeyView
	Error    string
}
