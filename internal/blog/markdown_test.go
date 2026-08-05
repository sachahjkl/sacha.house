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
	if !strings.Contains(html, "<h1>Heading</h1>") || !strings.Contains(html, "<img src=\"/image.png\" alt=\"secret alt\">") {
		t.Fatalf("RenderMarkdown() = %q", html)
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
