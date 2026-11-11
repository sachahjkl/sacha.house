package web

import (
	"strings"

	"github.com/a-h/templ"
)

// iconLabel names an emoji after its file: "file-folder" is "file folder".
func iconLabel(name string) string {
	return strings.ReplaceAll(name, "-", " ")
}

func iconURL(name string) templ.SafeURL {
	return templ.SafeURL("/static/icons/noto/" + name + ".svg")
}
