package web

type BrewMessage struct {
	Text  string
	Emoji string
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
}

type AdminBlogPostsPageData struct {
	PageData
	Posts []AdminBlogPostView
}

type BlogPostForm struct {
	IsNew       bool
	FormAction  string
	Title       string
	Slug        string
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
