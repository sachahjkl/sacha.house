package blog

import (
	"strings"
	"testing"
	"time"
)

func TestMarkdown(t *testing.T) {
	source := "# Heading\r\n\r\nHello *world*.\r\n\r\n![secret alt](/image.png)\r\n\r\n`code`\r\n"
	if got := NormalizeMarkdown(source); strings.Contains(got, "\r") {
		t.Fatalf("NormalizeMarkdown() retained CR: %q", got)
	}
	if got := PlainText(source); got != "Heading Hello world. code" {
		t.Fatalf("PlainText() = %q", got)
	}
	html, err := RenderMarkdown(source)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(html, "<h1 id=\"heading\">Heading</h1>") || !strings.Contains(html, "<img src=\"/image.png\" alt=\"secret alt\" loading=\"lazy\" decoding=\"async\">") {
		t.Fatalf("RenderMarkdown() = %q", html)
	}
}

func TestMermaidBlocksBecomeDiagrams(t *testing.T) {
	source := "Intro.\n\n```mermaid\ngraph TD\n  A[\"<b>x</b>\"] --> B\n```\n\n```go\nfmt.Println()\n```\n"
	html, err := RenderMarkdown(source)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(html, `<figure class="diagram diagram-missing"><pre class="mermaid">graph TD`) {
		t.Fatalf("diagram is not marked: %q", html)
	}
	if strings.Contains(html, "<b>") || !strings.Contains(html, "&lt;b&gt;x&lt;/b&gt;") {
		t.Fatalf("diagram source is not escaped: %q", html)
	}
	if !strings.Contains(html, `<pre><code class="language-go">`) {
		t.Fatalf("an ordinary code block changed: %q", html)
	}
	if got := PlainText(source); strings.Contains(got, "graph TD") {
		t.Fatalf("PlainText() contains the diagram source: %q", got)
	}
}

func TestTablesAndRawHTML(t *testing.T) {
	html, err := RenderMarkdown("| a | b |\n|---|---|\n| 1 | 2 |\n\n<script>alert(1)</script>\n")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(html, "<table>") || !strings.Contains(html, "<td>1</td>") {
		t.Fatalf("table is not rendered: %q", html)
	}
	if strings.Contains(html, "<script>") {
		t.Fatalf("raw HTML is not escaped: %q", html)
	}
}

func TestTableOfContents(t *testing.T) {
	source := "# Title\n\n## First part\n\ntext\n\n### A `code` detail\n\n## First part\n\n#### too deep\n"
	got := TableOfContents(source)
	want := []TOCEntry{
		{2, "first-part", "First part"},
		{3, "a-code-detail", "A code detail"},
		{2, "first-part-1", "First part"},
	}
	if len(got) != len(want) {
		t.Fatalf("TableOfContents() = %+v", got)
	}
	for index := range want {
		if got[index] != want[index] {
			t.Errorf("entry %d = %+v, want %+v", index, got[index], want[index])
		}
	}
	html, _ := RenderMarkdown(source)
	for _, entry := range want {
		if !strings.Contains(html, `id="`+entry.ID+`"`) {
			t.Errorf("the rendered heading has no id %q", entry.ID)
		}
	}
}

func TestExcerptShowsEscapedPunctuationAsWritten(t *testing.T) {
	if got := Excerpt(`\[DRAFT\] notes`, ExcerptLength); got != "[DRAFT] notes" {
		t.Fatalf("Excerpt() = %q", got)
	}
}

func TestExcerptUsesRunesAndWordBoundary(t *testing.T) {
	if got := Excerpt("one two three", 8); got != "one two..." {
		t.Fatalf("Excerpt() = %q", got)
	}
	if got := Excerpt("ééé z", 3); got != "ééé..." {
		t.Fatalf("Unicode Excerpt() = %q", got)
	}
	if got := Excerpt("short", ExcerptLength); got != "short" {
		t.Fatalf("short Excerpt() = %q", got)
	}
}

func TestParisDateConversions(t *testing.T) {
	winter, err := ParseLocalDateTime("2026-01-15T12:30")
	if err != nil || winter.Format(time.RFC3339) != "2026-01-15T11:30:00Z" {
		t.Fatalf("winter = %v, %v", winter, err)
	}
	summer, err := ParseLocalDateTime("2026-07-15T12:30")
	if err != nil || summer.Format(time.RFC3339) != "2026-07-15T10:30:00Z" {
		t.Fatalf("summer = %v, %v", summer, err)
	}
	if got, err := FormatLocalDateTime("2026-07-15T10:30:00Z"); err != nil || got != "2026-07-15T12:30" {
		t.Fatalf("FormatLocalDateTime() = %q, %v", got, err)
	}
	if _, err := ParseLocalDateTime("2026-02-30T12:00"); err == nil {
		t.Fatal("ParseLocalDateTime() accepted an invalid date")
	}
}
