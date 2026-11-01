package web

import "github.com/a-h/templ"

func iconURL(name string) templ.SafeURL {
	return templ.SafeURL("/static/icons/noto/" + name + ".svg")
}
