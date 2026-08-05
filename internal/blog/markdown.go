package blog

import (
	"bytes"
	"fmt"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/text"
)

const ExcerptLength = 180

var markdown = goldmark.New()

// NormalizeMarkdown converts all line endings to Unix line endings.
func NormalizeMarkdown(source string) string {
	return strings.ReplaceAll(strings.ReplaceAll(source, "\r\n", "\n"), "\r", "\n")
}

// RenderMarkdown converts CommonMark Markdown to HTML.
func RenderMarkdown(source string) (string, error) {
	var output bytes.Buffer
	if err := markdown.Convert([]byte(NormalizeMarkdown(source)), &output); err != nil {
		return "", fmt.Errorf("render markdown: %w", err)
	}
	return output.String(), nil
}

// PlainText extracts readable text and omits images and their alternative text.
func PlainText(markdownSource string) string {
	source := []byte(NormalizeMarkdown(markdownSource))
	document := markdown.Parser().Parse(text.NewReader(source))
	var output strings.Builder
	pendingSpace := false
	imageDepth := 0

	appendText := func(value []byte) {
		for len(value) > 0 {
			r, size := utf8.DecodeRune(value)
			value = value[size:]
			if unicode.IsSpace(r) {
				pendingSpace = true
				continue
			}
			if pendingSpace && output.Len() > 0 {
				output.WriteByte(' ')
			}
			pendingSpace = false
			output.WriteRune(r)
		}
	}

	_ = ast.Walk(document, func(node ast.Node, entering bool) (ast.WalkStatus, error) {
		if node.Kind() == ast.KindImage {
			if entering {
				imageDepth++
				pendingSpace = true
			} else {
				imageDepth--
			}
			return ast.WalkContinue, nil
		}
		if imageDepth > 0 {
			return ast.WalkContinue, nil
		}
		if !entering {
			switch node.Kind() {
			case ast.KindParagraph, ast.KindHeading, ast.KindList, ast.KindListItem, ast.KindBlockquote:
				pendingSpace = true
			}
			return ast.WalkContinue, nil
		}

		switch node := node.(type) {
		case *ast.Text:
			appendText(node.Segment.Value(source))
			if node.SoftLineBreak() || node.HardLineBreak() {
				pendingSpace = true
			}
		case *ast.String:
			appendText(node.Value)
		case *ast.CodeSpan:
			appendText(node.Text(source))
			return ast.WalkSkipChildren, nil
		case *ast.CodeBlock:
			appendSegments(node.Lines(), source, appendText)
			return ast.WalkSkipChildren, nil
		case *ast.FencedCodeBlock:
			appendSegments(node.Lines(), source, appendText)
			return ast.WalkSkipChildren, nil
		case *ast.ThematicBreak:
			pendingSpace = true
		}
		return ast.WalkContinue, nil
	})

	return strings.TrimSpace(output.String())
}

func appendSegments(segments *text.Segments, source []byte, appendText func([]byte)) {
	for i := 0; i < segments.Len(); i++ {
		segment := segments.At(i)
		appendText(segment.Value(source))
	}
}

// Excerpt extracts plain text and truncates it at a word boundary.
func Excerpt(source string, maxCharacters int) string {
	plain := strings.TrimSpace(PlainText(source))
	runes := []rune(plain)
	if maxCharacters <= 0 || len(runes) <= maxCharacters {
		return plain
	}

	cut := runes[:maxCharacters]
	lastSpace := -1
	for i, r := range cut {
		if unicode.IsSpace(r) {
			lastSpace = i
		}
	}
	if lastSpace > 0 {
		cut = cut[:lastSpace]
	}
	truncated := strings.TrimSpace(string(cut))
	if truncated == "" {
		truncated = strings.TrimSpace(string(runes[:maxCharacters]))
	}
	return truncated + "..."
}

// ParseLocalDateTime converts an HTML datetime-local value in Europe/Paris to UTC.
func ParseLocalDateTime(value string) (time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}, nil
	}
	location, err := time.LoadLocation("Europe/Paris")
	if err != nil {
		return time.Time{}, fmt.Errorf("load Europe/Paris: %w", err)
	}
	parsed, err := time.ParseInLocation("2006-01-02T15:04", value, location)
	if err != nil || parsed.Format("2006-01-02T15:04") != value {
		return time.Time{}, fmt.Errorf("published at must be a valid datetime")
	}
	return parsed.UTC(), nil
}

// FormatLocalDateTime converts an RFC 3339 timestamp to an Europe/Paris datetime-local value.
func FormatLocalDateTime(value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", nil
	}
	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return "", fmt.Errorf("parse timestamp: %w", err)
	}
	location, err := time.LoadLocation("Europe/Paris")
	if err != nil {
		return "", fmt.Errorf("load Europe/Paris: %w", err)
	}
	return parsed.In(location).Format("2006-01-02T15:04"), nil
}
