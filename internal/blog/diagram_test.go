package blog

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPrerenderedDiagramIsInlined(t *testing.T) {
	source := "```mermaid\n%% title: T\ngraph TD\n  A --> B\n```\n"
	hash := DiagramHash("%% title: T\ngraph TD\n  A --> B\n")
	diagrams := Diagrams{hash: {Title: "T", Width: 10, Height: 5,
		Light: "<!-- light -->\n<svg width=\"10\"><title>L</title></svg>\n",
		Dark:  "<!-- dark -->\n<svg width=\"10\"><title>D</title></svg>\n"}}
	html, err := RenderMarkdownWithDiagrams(source, diagrams)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`diagram-ready`, `<svg class="diagram-light" width="10">`, `<svg class="diagram-dark" width="10">`, `pre class="diagram-source" hidden>%% title: T`, `data-title="T"`} {
		if !strings.Contains(html, want) {
			t.Errorf("rendered diagram lacks %q: %s", want, html)
		}
	}
	if strings.Contains(html, `class="mermaid"`) {
		t.Errorf("a drawn diagram still has a Mermaid block: %s", html)
	}
}

func TestStaleDiagramFallsBackToSource(t *testing.T) {
	diagrams := Diagrams{DiagramHash("other"): {Light: "<svg></svg>", Dark: "<svg></svg>"}}
	html, err := RenderMarkdownWithDiagrams("```mermaid\ngraph TD\n```\n", diagrams)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(html, "diagram-missing") {
		t.Fatalf("a block without its drawing must show its source: %s", html)
	}
}

func TestLoadDiagramsDropsEntriesWithoutFiles(t *testing.T) {
	post := t.TempDir()
	directory := filepath.Join(post, "assets", "diagrams")
	if err := os.MkdirAll(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	manifest := `{"0123456789abcdef":{"title":"a"},"fedcba9876543210":{"title":"b"},"../escape":{"title":"c"}}`
	files := map[string]string{
		"index.json":                 manifest,
		"0123456789abcdef-light.svg": "<svg>l</svg>",
		"0123456789abcdef-dark.svg":  "<svg>d</svg>",
		"fedcba9876543210-light.svg": "<svg>l</svg>",
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(directory, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got := LoadDiagrams(post)
	if len(got) != 1 || got["0123456789abcdef"].Light != "<svg>l</svg>" || got["0123456789abcdef"].Dark != "<svg>d</svg>" {
		t.Fatalf("LoadDiagrams() = %+v", got)
	}
	if LoadDiagrams(t.TempDir()) != nil {
		t.Fatal("a post without a manifest has no diagrams")
	}
}

// The hash of the Go side must match tools/diagrams.ts, or no prerendered diagram is ever found.
func TestDiagramHashMatchesTool(t *testing.T) {
	if got := DiagramHash("  graph TD\r\n  A --> B\r\n\n"); got != DiagramHash("graph TD\n  A --> B") {
		t.Fatalf("hash depends on line endings or padding: %s", got)
	}
}

// Every diagram of the posts shipped in data/blog has been drawn by tools/diagrams.ts, and the hash the Go side
// computes finds it. It fails when a post gains or changes a diagram without `just diagrams`.
func TestShippedPostsHavePrerenderedDiagrams(t *testing.T) {
	root := filepath.Join("..", "..", "data", "blog")
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Skip("no data/blog")
	}
	drawn := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		content, err := os.ReadFile(filepath.Join(root, entry.Name(), "content.md"))
		if err != nil {
			continue
		}
		html, err := RenderMarkdownWithDiagrams(string(content), LoadDiagrams(filepath.Join(root, entry.Name())))
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(html, "diagram-missing") {
			t.Errorf("%s: a diagram was not prerendered; run `just diagrams`", entry.Name())
		}
		drawn += strings.Count(html, "diagram-ready")
	}
	if drawn == 0 {
		t.Error("no prerendered diagram found in data/blog")
	}
}
