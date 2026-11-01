package web

// KeyPageData describes a page that shows a public key as text.
type KeyPageData struct {
	PageData
	Heading     string
	Description string
	Key         string
	RawPath     string
}
