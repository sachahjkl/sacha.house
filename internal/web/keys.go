package web

// KeyView is one public key shown on a page.
type KeyView struct {
	ID      string
	Heading string
	Key     string
	Path    string // HTML page showing the key
	RawPath string // raw file
}

// KeyPageData describes a page that shows one or several public keys as text.
type KeyPageData struct {
	PageData
	Heading     string
	Description string
	Keys        []KeyView
}
