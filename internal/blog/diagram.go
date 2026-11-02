package blog

import (
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/renderer"
	"github.com/yuin/goldmark/text"
	"github.com/yuin/goldmark/util"
)

// kindDiagram is the node a ```mermaid fenced block becomes. The diagram itself is drawn in the browser
// (static/js/post.js loads Mermaid only on pages that have one); the server only marks the source.
var kindDiagram = ast.NewNodeKind("Diagram")

type diagramNode struct {
	ast.BaseBlock
}

func (node *diagramNode) Kind() ast.NodeKind { return kindDiagram }
func (node *diagramNode) IsRaw() bool        { return true }
func (node *diagramNode) Dump(source []byte, level int) {
	ast.DumpHelper(node, source, level, nil, nil)
}

type diagramTransformer struct{}

func (diagramTransformer) Transform(document *ast.Document, reader text.Reader, _ parser.Context) {
	var blocks []*ast.FencedCodeBlock
	_ = ast.Walk(document, func(node ast.Node, entering bool) (ast.WalkStatus, error) {
		if block, ok := node.(*ast.FencedCodeBlock); ok && entering && strings.EqualFold(string(block.Language(reader.Source())), "mermaid") {
			blocks = append(blocks, block)
		}
		return ast.WalkContinue, nil
	})
	for _, block := range blocks {
		diagram := &diagramNode{}
		diagram.SetLines(block.Lines())
		block.Parent().ReplaceChild(block.Parent(), block, diagram)
	}
}

type diagramRenderer struct{}

func (diagramRenderer) RegisterFuncs(registerer renderer.NodeRendererFuncRegisterer) {
	registerer.Register(kindDiagram, func(writer util.BufWriter, source []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		_, _ = writer.WriteString(`<figure class="diagram"><pre class="mermaid">`)
		lines := node.Lines()
		for index := 0; index < lines.Len(); index++ {
			line := lines.At(index)
			_, _ = writer.Write(util.EscapeHTML(line.Value(source)))
		}
		_, _ = writer.WriteString("</pre></figure>\n")
		return ast.WalkSkipChildren, nil
	})
}

type diagrams struct{}

// Extend registers the diagram transformer and renderer.
func (diagrams) Extend(markdown goldmark.Markdown) {
	markdown.Parser().AddOptions(parser.WithASTTransformers(util.Prioritized(diagramTransformer{}, 100)))
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
			if title := headingText(heading, source); id != "" && title != "" {
				entries = append(entries, TOCEntry{Level: heading.Level, ID: id, Title: title})
			}
		}
		return ast.WalkSkipChildren, nil
	})
	return entries
}

func headingText(heading *ast.Heading, source []byte) string {
	var builder strings.Builder
	_ = ast.Walk(heading, func(node ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		switch typed := node.(type) {
		case *ast.Text:
			builder.Write(typed.Segment.Value(source))
		case *ast.String:
			builder.Write(typed.Value)
		}
		return ast.WalkContinue, nil
	})
	return strings.TrimSpace(builder.String())
}
