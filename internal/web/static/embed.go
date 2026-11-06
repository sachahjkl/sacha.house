package static

import "embed"

// Files contains the static assets of the site.
//
//go:embed css fonts icons js share *.gpg *.ico *.jpg *.pdf *.pdn *.png *.pub *.svg *.txt *.webmanifest *.webp *.xml
var Files embed.FS
