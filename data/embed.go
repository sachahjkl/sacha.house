// Package data embeds the blog posts of the repository. The server copies the ones a data directory does not have
// yet when it starts, so a post written in the repository is published by a deployment.
package data

import "embed"

// Blog holds data/blog: one directory per post (post.json, content.md and an assets directory).
//
//go:embed blog
var Blog embed.FS
