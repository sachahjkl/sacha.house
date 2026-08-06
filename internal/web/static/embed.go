package static

import "embed"

// Files contains static assets and the internal LinkedIn profile snapshot.
//
//go:embed css fonts gifs js share *.gpg *.html *.ico *.jpg *.json *.pdf *.pdn *.png *.pub *.svg *.txt *.webmanifest *.xml
var Files embed.FS
