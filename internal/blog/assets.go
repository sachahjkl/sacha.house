package blog

import (
	"image"
	_ "image/gif"  // registers GIF for image.DecodeConfig
	_ "image/jpeg" // registers JPEG for image.DecodeConfig
	_ "image/png"  // registers PNG for image.DecodeConfig
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	_ "golang.org/x/image/webp" // registers WebP for image.DecodeConfig

	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/text"
)

// PostAssets locates the files of one post for the renderer. The zero value renders a post without them: its
// diagrams show their source, and its images have no dimensions.
type PostAssets struct {
	// Directory is the assets directory of the post on disk.
	Directory string
	// URL is the public address of Directory, without a trailing slash.
	URL      string
	Diagrams Diagrams
}

var assetsContextKey = parser.NewContextKey()

func assetsFromContext(context parser.Context) PostAssets {
	if value, ok := context.Get(assetsContextKey).(PostAssets); ok {
		return value
	}
	return PostAssets{}
}

// imageTransformer gives every image of a post lazy loading, and the images of the post's own assets their
// width and height, so the page does not move while they load.
type imageTransformer struct{}

func (imageTransformer) Transform(document *ast.Document, _ text.Reader, context parser.Context) {
	assets := assetsFromContext(context)
	_ = ast.Walk(document, func(node ast.Node, entering bool) (ast.WalkStatus, error) {
		image, ok := node.(*ast.Image)
		if !ok || !entering {
			return ast.WalkContinue, nil
		}
		image.SetAttributeString("loading", []byte("lazy"))
		image.SetAttributeString("decoding", []byte("async"))
		if width, height, found := assets.imageSize(string(image.Destination)); found {
			image.SetAttributeString("width", []byte(strconv.Itoa(width)))
			image.SetAttributeString("height", []byte(strconv.Itoa(height)))
		}
		return ast.WalkContinue, nil
	})
}

// imageSize reads the dimensions of an image of the post's assets from its header.
func (assets PostAssets) imageSize(destination string) (int, int, bool) {
	if assets.Directory == "" || assets.URL == "" {
		return 0, 0, false
	}
	name, found := strings.CutPrefix(destination, assets.URL+"/")
	if !found || !fs.ValidPath(name) {
		return 0, 0, false
	}
	file, err := os.Open(filepath.Join(assets.Directory, filepath.FromSlash(name)))
	if err != nil {
		return 0, 0, false
	}
	defer file.Close()
	config, _, err := image.DecodeConfig(file)
	if err != nil || config.Width <= 0 || config.Height <= 0 {
		return 0, 0, false
	}
	return config.Width, config.Height, true
}

// Cover is the picture of a post's link previews: the first image of its own assets.
type Cover struct {
	// URL is relative to the site, such as /media/blog/slug/assets/a.png.
	URL    string
	Alt    string
	Width  int
	Height int
}

// Cover finds the first image of the post's assets whose dimensions are known.
func (assets PostAssets) Cover(markdownSource string) (Cover, bool) {
	source := []byte(NormalizeMarkdown(markdownSource))
	document := markdown.Parser().Parse(text.NewReader(source))
	var cover Cover
	found := false
	_ = ast.Walk(document, func(node ast.Node, entering bool) (ast.WalkStatus, error) {
		image, ok := node.(*ast.Image)
		if !ok || !entering || found {
			return ast.WalkContinue, nil
		}
		destination := string(image.Destination)
		if width, height, sized := assets.imageSize(destination); sized {
			cover = Cover{URL: destination, Alt: inlineText(image, source), Width: width, Height: height}
			found = true
			return ast.WalkStop, nil
		}
		return ast.WalkSkipChildren, nil
	})
	return cover, found
}
