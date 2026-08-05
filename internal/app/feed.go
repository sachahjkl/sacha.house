package app

import (
	"bytes"
	"encoding/xml"
	"io"
	"net/http"
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
		writeXMLText(&output, "    ", "updated", post.Metadata.PublishedAt)
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
