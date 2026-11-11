package blog

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"html"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/renderer"
	"github.com/yuin/goldmark/text"
	"github.com/yuin/goldmark/util"
)

// Diagram is one ```mermaid block, drawn ahead of time by tools/diagrams.ts into two SVGs: one for the light
// scheme and one for the dark scheme. The site never draws a diagram in the browser.
type Diagram struct {
	Title  string `json:"title"`
	Width  int    `json:"width"`
	Height int    `json:"height"`

	// LightURL and DarkURL are the public addresses of the two drawings.
	LightURL string `json:"-"`
	DarkURL  string `json:"-"`
}

// Diagrams maps the hash of a block's source to the diagram that was drawn from it.
type Diagrams map[string]Diagram

const (
	// diagramDirectory holds the prerendered SVGs and their manifest, inside a post's assets.
	diagramDirectory = "diagrams"
	diagramManifest  = "index.json"
	// diagramHashLength is how much of the SHA-256 of a block tools/diagrams.ts keeps in a file name.
	diagramHashLength = 16
)

var diagramHashPattern = regexp.MustCompile(`^[0-9a-f]{16}$`)

// DiagramHash identifies a block by its source. tools/diagrams.ts computes it the same way: the normalized
// source, trimmed, hashed with SHA-256.
func DiagramHash(source string) string {
	sum := sha256.Sum256([]byte(strings.TrimSpace(NormalizeMarkdown(source))))
	return hex.EncodeToString(sum[:])[:diagramHashLength]
}

// LoadDiagrams reads the manifest of the SVGs a post has under its assets directory. assetsURL is the public
// address of that directory. A manifest entry whose files are missing is dropped, so the block falls back to its
// source instead of showing a broken diagram.
func LoadDiagrams(assetsDirectory, assetsURL string) Diagrams {
	directory := filepath.Join(assetsDirectory, diagramDirectory)
	content, err := os.ReadFile(filepath.Join(directory, diagramManifest))
	if err != nil {
		return nil
	}
	var manifest map[string]Diagram
	if err := json.Unmarshal(content, &manifest); err != nil {
		return nil
	}
	diagrams := make(Diagrams, len(manifest))
	for hash, diagram := range manifest {
		if !diagramHashPattern.MatchString(hash) {
			continue
		}
		if !isFile(filepath.Join(directory, hash+"-light.svg")) || !isFile(filepath.Join(directory, hash+"-dark.svg")) {
			continue
		}
		diagram.LightURL = assetsURL + "/" + diagramDirectory + "/" + hash + "-light.svg"
		diagram.DarkURL = assetsURL + "/" + diagramDirectory + "/" + hash + "-dark.svg"
		diagrams[hash] = diagram
	}
	if len(diagrams) == 0 {
		return nil
	}
	return diagrams
}

func isFile(name string) bool {
	info, err := os.Stat(name)
	return err == nil && info.Mode().IsRegular()
}

// kindDiagram is the node a ```mermaid fenced block becomes.
var kindDiagram = ast.NewNodeKind("Diagram")

type diagramNode struct {
	ast.BaseBlock
	source  []byte
	diagram *Diagram
	index   int
}

func (node *diagramNode) Kind() ast.NodeKind { return kindDiagram }
func (node *diagramNode) IsRaw() bool        { return true }
func (node *diagramNode) Dump(source []byte, level int) {
	ast.DumpHelper(node, source, level, nil, nil)
}

type diagramTransformer struct{}

func (diagramTransformer) Transform(document *ast.Document, reader text.Reader, context parser.Context) {
	available := assetsFromContext(context).Diagrams
	var blocks []*ast.FencedCodeBlock
	_ = ast.Walk(document, func(node ast.Node, entering bool) (ast.WalkStatus, error) {
		if block, ok := node.(*ast.FencedCodeBlock); ok && entering && strings.EqualFold(string(block.Language(reader.Source())), "mermaid") {
			blocks = append(blocks, block)
		}
		return ast.WalkContinue, nil
	})
	for index, block := range blocks {
		diagram := &diagramNode{index: index + 1}
		diagram.SetLines(block.Lines())
		diagram.source = blockLines(block, reader.Source())
		if drawn, ok := available[DiagramHash(string(diagram.source))]; ok {
			diagram.diagram = &drawn
		}
		block.Parent().ReplaceChild(block.Parent(), block, diagram)
	}
}

func blockLines(block *ast.FencedCodeBlock, source []byte) []byte {
	var builder strings.Builder
	lines := block.Lines()
	for index := 0; index < lines.Len(); index++ {
		segment := lines.At(index)
		builder.Write(segment.Value(source))
	}
	return []byte(builder.String())
}

type diagramRenderer struct{}

func (diagramRenderer) RegisterFuncs(registerer renderer.NodeRendererFuncRegisterer) {
	registerer.Register(kindDiagram, func(writer util.BufWriter, _ []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		diagram, ok := node.(*diagramNode)
		if !ok {
			return ast.WalkSkipChildren, nil
		}
		if diagram.diagram == nil {
			writeDiagramSource(writer, diagram)
		} else {
			writeDiagram(writer, diagram)
		}
		return ast.WalkSkipChildren, nil
	})
}

// writeDiagramSource shows the source of a block that was never drawn. The site has no client-side renderer
// left, so this is the honest fallback: the reader still sees what the diagram says.
func writeDiagramSource(writer util.BufWriter, node *diagramNode) {
	_, _ = writer.WriteString(`<figure class="diagram diagram-missing"><pre class="mermaid">`)
	_, _ = writer.Write(util.EscapeHTML(node.source))
	_, _ = writer.WriteString("</pre></figure>\n")
}

// writeDiagram reserves the room of the drawing and names its two SVGs. static/js/post.js inlines the SVG of
// the reader's scheme when the figure comes near the screen: inline, because the drawings use the page's font,
// and on demand, because a long post has dozens of them. A reader without scripts gets the drawings as images.
// The source is kept, hidden, for the copy button.
func writeDiagram(writer util.BufWriter, node *diagramNode) {
	diagram := node.diagram
	title := html.EscapeString(diagram.Title)
	if title == "" {
		title = "Diagram " + strconv.Itoa(node.index)
	}
	width, height := strconv.Itoa(max(diagram.Width, 1)), strconv.Itoa(max(diagram.Height, 1))
	light, dark := html.EscapeString(diagram.LightURL), html.EscapeString(diagram.DarkURL)
	_, _ = writer.WriteString(`<figure class="diagram diagram-ready" id="diagram-`)
	_, _ = writer.WriteString(strconv.Itoa(node.index))
	_, _ = writer.WriteString(`" data-title="` + title + `">`)
	_, _ = writer.WriteString(`<div class="diagram-tools"><span class="diagram-label">` + title + `</span>`)
	_, _ = writer.WriteString(`<button type="button" data-action="expand" title="Open in the viewer: pan, zoom, full screen">expand</button>`)
	_, _ = writer.WriteString(`<button type="button" data-action="download" title="Download the diagram as SVG">svg</button>`)
	_, _ = writer.WriteString(`<button type="button" data-action="copy" title="Copy the Mermaid source">source</button></div>`)
	_, _ = writer.WriteString(`<div class="diagram-body" data-light="` + light + `" data-dark="` + dark + `">`)
	_, _ = writer.WriteString(`<span class="diagram-slot" role="img" aria-label="` + title + `" style="width:` + width + `px;aspect-ratio:` + width + `/` + height + `"></span>`)
	_, _ = writer.WriteString(`<noscript><picture><source media="(prefers-color-scheme: dark)" srcset="` + dark + `">`)
	_, _ = writer.WriteString(`<img src="` + light + `" alt="` + title + `" width="` + width + `" height="` + height + `" loading="lazy" decoding="async"></picture></noscript>`)
	_, _ = writer.WriteString(`</div><pre class="diagram-source" hidden>`)
	_, _ = writer.Write(util.EscapeHTML(node.source))
	_, _ = writer.WriteString("</pre></figure>\n")
}

type diagrams struct{}

// Extend registers the diagram transformer and renderer.
func (diagrams) Extend(markdown goldmark.Markdown) {
	markdown.Parser().AddOptions(parser.WithASTTransformers(
		util.Prioritized(diagramTransformer{}, 100), util.Prioritized(imageTransformer{}, 200)))
	markdown.Renderer().AddOptions(renderer.WithNodeRenderers(util.Prioritized(diagramRenderer{}, 100)))
}

// TOCEntry is one heading of a table of contents.
type TOCEntry struct {
	Level int
	ID    string
	Title string
}

// TableOfContents lists the level 2 and 3 headings of a post with the anchors the renderer gave them.
func TableOfContents(markdownSource string) []TOCEntry {
	source := []byte(NormalizeMarkdown(markdownSource))
	document := markdown.Parser().Parse(text.NewReader(source))
	var entries []TOCEntry
	_ = ast.Walk(document, func(node ast.Node, entering bool) (ast.WalkStatus, error) {
		heading, ok := node.(*ast.Heading)
		if !ok || !entering {
			return ast.WalkContinue, nil
		}
		if heading.Level >= 2 && heading.Level <= 3 {
			id := ""
			value, _ := heading.AttributeString("id")
			switch typed := value.(type) {
			case []byte:
				id = string(typed)
			case string:
				id = typed
			}
			if title := inlineText(heading, source); id != "" && title != "" {
				entries = append(entries, TOCEntry{Level: heading.Level, ID: id, Title: title})
			}
		}
		return ast.WalkSkipChildren, nil
	})
	return entries
}

// inlineText is the text of an inline node and its children, such as a heading or the alternative text of an image.
func inlineText(node ast.Node, source []byte) string {
	var builder strings.Builder
	_ = ast.Walk(node, func(child ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		switch typed := child.(type) {
		case *ast.Text:
			builder.Write(typed.Segment.Value(source))
		case *ast.String:
			builder.Write(typed.Value)
		}
		return ast.WalkContinue, nil
	})
	return strings.TrimSpace(builder.String())
}
