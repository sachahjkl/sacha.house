package app

import (
	"bytes"
	"encoding/xml"
	"io"
	"net/http"
	"strings"
	"time"

	"sacha.house/internal/blog"
	"sacha.house/internal/web"
)

type feedPost struct {
	Metadata blog.Metadata
	Date     time.Time
}

func (app *App) feedPosts() ([]feedPost, error) {
	metadata, err := app.blog.List(false)
	if err != nil {
		return nil, err
	}
	posts := make([]feedPost, len(metadata))
	for index, post := range metadata {
		posts[index] = feedPost{Metadata: post, Date: parseTime(post.PublishedAt)}
	}
	return posts, nil
}

// sitemapPages are the public pages listed in the sitemap, next to the blog posts.
var sitemapPages = [...]string{"/", "/projects", "/blog", "/about", "/resume", "/cv", "/keys"}

// postModified is the date a post last changed: its last update, or its publication.
func postModified(metadata blog.Metadata) time.Time {
	if updated := parseTime(metadata.UpdatedAt); !updated.IsZero() {
		return updated
	}
	return parseTime(metadata.PublishedAt)
}

func (app *App) sitemap(writer http.ResponseWriter, _ *http.Request) {
	posts, err := app.feedPosts()
	if err != nil {
		http.Error(writer, "failed to load blog", http.StatusInternalServerError)
		return
	}
	// The home page and the blog index list the posts: they change when a post does.
	var newest time.Time
	for _, post := range posts {
		if modified := postModified(post.Metadata); modified.After(newest) {
			newest = modified
		}
	}
	var output bytes.Buffer
	output.WriteString("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n")
	for _, page := range sitemapPages {
		output.WriteString("  <url>\n")
		writeXMLText(&output, "    ", "loc", web.SiteURL+page)
		if (page == "/" || page == "/blog") && !newest.IsZero() {
			writeXMLText(&output, "    ", "lastmod", newest.UTC().Format("2006-01-02"))
		}
		output.WriteString("  </url>\n")
	}
	for _, post := range posts {
		output.WriteString("  <url>\n")
		writeXMLText(&output, "    ", "loc", web.SiteURL+"/blog/"+post.Metadata.Slug)
		writeXMLText(&output, "    ", "lastmod", postModified(post.Metadata).UTC().Format("2006-01-02"))
		output.WriteString("  </url>\n")
	}
	output.WriteString("</urlset>\n")
	writer.Header().Set("Content-Type", "application/xml; charset=utf-8")
	writer.Header().Set("Cache-Control", publicCache)
	_, _ = writer.Write(output.Bytes())
}

// llmsText serves /llms.txt (https://llmstxt.org): what the site is and its pages, in Markdown, for language
// models and answer engines.
func (app *App) llmsText(writer http.ResponseWriter, _ *http.Request) {
	metadata, err := app.blog.List(false)
	if err != nil {
		http.Error(writer, "failed to load blog", http.StatusInternalServerError)
		return
	}
	var output strings.Builder
	output.WriteString("# sacha.house\n\n")
	output.WriteString("> The personal website of " + web.Me.FullName + ", software engineer in France: projects, writing, career, and contact.\n\n")
	output.WriteString("Featured projects: Wren, a web browser where WebAssembly runs everything; gui_toolkit, an immediate-mode GUI toolkit in Odin; native desktop clients.\n\n")
	output.WriteString("Contact: " + web.Me.Mail + ". GitHub: " + web.Me.GitHub + ". LinkedIn: " + web.Me.LinkedIn + ".\n\n")
	output.WriteString("## Pages\n\n")
	for _, page := range [...]struct{ path, title, description string }{
		{"/", "Home", "Who " + web.Me.FullName + " is, featured projects, and the latest posts."},
		{"/about", "About", "Biography, career, education, and contact details."},
		{"/projects", "Projects", "Every public project, with the featured ones first."},
		{"/resume", "Résumé", "One-page résumé, in French; add ?lang=en for English."},
		{"/cv", "Curriculum vitae", "Full curriculum vitae, in French; add ?lang=en for English."},
		{"/blog", "Blog", "Every post, newest first. Feeds: /blog/rss.xml and /blog/atom.xml."},
	} {
		output.WriteString("- [" + page.title + "](" + web.SiteURL + page.path + "): " + page.description + "\n")
	}
	output.WriteString("\n## Blog posts\n\n")
	for _, post := range metadata {
		description := post.Description
		if description == "" {
			if document, err := app.blog.Load(post.Slug, false); err == nil {
				description = postDescription(document)
			}
		}
		output.WriteString("- [" + post.Title + "](" + web.SiteURL + "/blog/" + post.Slug + ")")
		if description != "" {
			output.WriteString(": " + description)
		}
		output.WriteString("\n")
	}
	writer.Header().Set("Content-Type", "text/plain; charset=utf-8")
	writer.Header().Set("Cache-Control", feedCache)
	_, _ = io.WriteString(writer, output.String())
}

func (app *App) rss(writer http.ResponseWriter, _ *http.Request) {
	posts, err := app.feedPosts()
	if err != nil {
		http.Error(writer, "failed to load blog", http.StatusInternalServerError)
		return
	}
	var output bytes.Buffer
	output.WriteString("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<rss version=\"2.0\">\n  <channel>\n")
	writeXMLText(&output, "    ", "title", "sacha.house blog")
	writeXMLText(&output, "    ", "link", "https://sacha.house/blog")
	writeXMLText(&output, "    ", "description", web.Me.FullName+"'s personal blog.")
	writeXMLText(&output, "    ", "language", "en-us")
	if len(posts) != 0 {
		writeXMLText(&output, "    ", "lastBuildDate", posts[0].Date.Format(time.RFC1123Z))
	}
	for _, post := range posts {
		link := "https://sacha.house/blog/" + post.Metadata.Slug
		output.WriteString("    <item>\n")
		writeXMLText(&output, "      ", "title", post.Metadata.Title)
		writeXMLText(&output, "      ", "link", link)
		writeXMLText(&output, "      ", "guid", link)
		writeXMLText(&output, "      ", "pubDate", post.Date.Format(time.RFC1123Z))
		if post.Metadata.Description != "" {
			writeXMLText(&output, "      ", "description", post.Metadata.Description)
		}
		writeXMLText(&output, "      ", "author", post.Metadata.Author)
		output.WriteString("    </item>\n")
	}
	output.WriteString("  </channel>\n</rss>\n")
	writer.Header().Set("Content-Type", "application/rss+xml; charset=utf-8")
	writer.Header().Set("Cache-Control", feedCache)
	_, _ = writer.Write(output.Bytes())
}

func (app *App) atom(writer http.ResponseWriter, _ *http.Request) {
	posts, err := app.feedPosts()
	if err != nil {
		http.Error(writer, "failed to load blog", http.StatusInternalServerError)
		return
	}
	var output bytes.Buffer
	output.WriteString("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\">\n")
	writeXMLText(&output, "  ", "title", "sacha.house blog")
	writeXMLText(&output, "  ", "subtitle", web.Me.FullName+"'s personal blog")
	output.WriteString("  <link href=\"https://sacha.house/blog\"/>\n  <link href=\"https://sacha.house/blog/atom.xml\" rel=\"self\"/>\n")
	if len(posts) != 0 {
		writeXMLText(&output, "  ", "updated", posts[0].Metadata.PublishedAt)
	}
	output.WriteString("  <author>\n")
	writeXMLText(&output, "    ", "name", web.Me.FullName)
	writeXMLText(&output, "    ", "email", web.Me.Mail)
	output.WriteString("  </author>\n")
	writeXMLText(&output, "  ", "id", "https://sacha.house/blog")
	for _, post := range posts {
		link := "https://sacha.house/blog/" + post.Metadata.Slug
		output.WriteString(`  <entry xml:lang="` + post.Metadata.Language + `">` + "\n")
		writeXMLText(&output, "    ", "title", post.Metadata.Title)
		output.WriteString(`    <link href="`)
		_ = xml.EscapeText(&output, []byte(link))
		output.WriteString("\"/>\n")
		writeXMLText(&output, "    ", "id", link)
		writeXMLText(&output, "    ", "published", post.Metadata.PublishedAt)
		writeXMLText(&output, "    ", "updated", postModified(post.Metadata).UTC().Format(time.RFC3339))
		if post.Metadata.Description != "" {
			writeXMLText(&output, "    ", "summary", post.Metadata.Description)
		}
		output.WriteString("    <author>\n")
		writeXMLText(&output, "      ", "name", post.Metadata.Author)
		output.WriteString("    </author>\n  </entry>\n")
	}
	output.WriteString("</feed>\n")
	writer.Header().Set("Content-Type", "application/atom+xml; charset=utf-8")
	writer.Header().Set("Cache-Control", feedCache)
	_, _ = writer.Write(output.Bytes())
}

func writeXMLText(writer io.Writer, indent, name, value string) {
	_, _ = io.WriteString(writer, indent+"<"+name+">")
	_ = xml.EscapeText(writer, []byte(value))
	_, _ = io.WriteString(writer, "</"+name+">\n")
}
