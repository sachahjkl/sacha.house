package blog

import (
	"bytes"
	"image"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPrerenderedDiagramIsLoadedOnDemand(t *testing.T) {
	source := "```mermaid\n%% title: T\ngraph TD\n  A --> B\n```\n"
	hash := DiagramHash("%% title: T\ngraph TD\n  A --> B\n")
	diagrams := Diagrams{hash: {Title: "T", Width: 10, Height: 5, LightURL: "/m/l.svg", DarkURL: "/m/d.svg"}}
	html, err := RenderPost(source, PostAssets{Diagrams: diagrams})
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`diagram-ready`, `data-light="/m/l.svg"`, `data-dark="/m/d.svg"`,
		`style="width:10px;aspect-ratio:10/5"`, `<source media="(prefers-color-scheme: dark)" srcset="/m/d.svg">`,
		`<img src="/m/l.svg" alt="T" width="10" height="5" loading="lazy"`, `pre class="diagram-source" hidden>%% title: T`, `data-title="T"`} {
		if !strings.Contains(html, want) {
			t.Errorf("rendered diagram lacks %q: %s", want, html)
		}
	}
	if strings.Contains(html, `class="mermaid"`) || strings.Contains(html, "<svg") {
		t.Errorf("a drawn diagram is inlined or still has a Mermaid block: %s", html)
	}
}

func TestStaleDiagramFallsBackToSource(t *testing.T) {
	diagrams := Diagrams{DiagramHash("other"): {LightURL: "/l.svg", DarkURL: "/d.svg"}}
	html, err := RenderPost("```mermaid\ngraph TD\n```\n", PostAssets{Diagrams: diagrams})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(html, "diagram-missing") {
		t.Fatalf("a block without its drawing must show its source: %s", html)
	}
}

func TestLoadDiagramsDropsEntriesWithoutFiles(t *testing.T) {
	assets := t.TempDir()
	directory := filepath.Join(assets, "diagrams")
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
	got := LoadDiagrams(assets, "/media/blog/p/assets")
	if len(got) != 1 || got["0123456789abcdef"].LightURL != "/media/blog/p/assets/diagrams/0123456789abcdef-light.svg" ||
		got["0123456789abcdef"].DarkURL != "/media/blog/p/assets/diagrams/0123456789abcdef-dark.svg" {
		t.Fatalf("LoadDiagrams() = %+v", got)
	}
	if LoadDiagrams(t.TempDir(), "/x") != nil {
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
		directory := filepath.Join(root, entry.Name(), "assets")
		html, err := RenderPost(string(content), PostAssets{Diagrams: LoadDiagrams(directory, "/media/blog/"+entry.Name()+"/assets")})
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

func TestPostImagesGetDimensionsAndLazyLoading(t *testing.T) {
	directory := t.TempDir()
	picture := image.NewRGBA(image.Rect(0, 0, 7, 3))
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, picture); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "a.png"), encoded.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	assets := PostAssets{Directory: directory, URL: "/media/blog/p/assets"}
	html, err := RenderPost("![A](/media/blog/p/assets/a.png)\n\n![B](/media/blog/p/assets/missing.png)\n\n![C](/media/blog/p/assets/../x.png)\n", assets)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`alt="A" loading="lazy" decoding="async" width="7" height="3"`, `alt="B" loading="lazy" decoding="async">`, `alt="C" loading="lazy" decoding="async">`} {
		if !strings.Contains(html, want) {
			t.Errorf("rendered images lack %q: %s", want, html)
		}
	}
}
