package web

import (
	"strconv"
	"strings"
	"time"
)

type NavItem struct {
	Title    string
	Pathname string
	Icon     string
	IsActive bool
}

var defaultNavItems = [...]NavItem{
	{Title: "projects", Pathname: "/projects", Icon: "file-folder"},
	{Title: "blog", Pathname: "/blog", Icon: "memo"},
	{Title: "about", Pathname: "/about", Icon: "scroll"},
	{Title: "résumé", Pathname: "/resume", Icon: "page-facing-up"},
}

func NavItems(activePathname string) []NavItem {
	items := make([]NavItem, len(defaultNavItems))
	copy(items, defaultNavItems[:])

	for i := range items {
		if items[i].Pathname == "/resume" {
			items[i].IsActive = strings.HasPrefix(activePathname, "/resume") || strings.HasPrefix(activePathname, "/cv")
		} else {
			items[i].IsActive = strings.HasPrefix(activePathname, items[i].Pathname)
		}
	}

	return items
}

// SiteURL is the public origin of the site, used wherever an absolute URL is required.
const SiteURL = "https://sacha.house"

type SEO struct {
	Title       string
	Description string
	Author      string
	// Image is the absolute URL of the link preview picture. ImageWidth and ImageHeight are its size in pixels.
	Image       string
	ImageAlt    string
	ImageWidth  int
	ImageHeight int
	URL         string
	Type        string
	NoIndex     bool
	// PublishedTime and ModifiedTime are the RFC 3339 dates of an article.
	PublishedTime string
	ModifiedTime  string
	// StructuredData is the schema.org description of the page, written as JSON-LD. Nil writes none.
	StructuredData any
}

// Default link preview picture.
const (
	defaultImage       = SiteURL + "/static/og.png"
	defaultImageAlt    = "sacha.house"
	defaultImageWidth  = 1200
	defaultImageHeight = 630
)

type Footer struct {
	Year       int
	CommitHash string
	GitRepoID  string
	Version    string
}

type PageData struct {
	Title        string
	Language     string
	SEO          SEO
	Footer       Footer
	NavItems     []NavItem
	StyleVersion string
	HotReload    bool
	AdminScripts bool
	// SearchScripts loads static/js/highlight.js: the highlighting of search matches.
	SearchScripts bool
	// PostScripts loads static/js/post.js: the image and diagram viewer and the Mermaid loader.
	PostScripts bool
	// HomeIsActive marks the site name in the header as the current page.
	HomeIsActive bool
}

// Locale is the Open Graph locale of the page.
func (data PageData) Locale() string {
	if data.Language == "fr" {
		return "fr_FR"
	}
	return "en_US"
}

type PageOptions struct {
	ActivePathname string
	Language       string
	SEO            SEO
	CommitHash     string
	GitRepoID      string
	Version        string
	StyleVersion   string
	HotReload      bool
	Now            time.Time
}

func NewPageData(options PageOptions) PageData {
	seo := options.SEO
	if seo.Title == "" {
		seo.Title = Me.SiteTitle
	}
	if seo.Description == "" {
		seo.Description = Me.SiteTitle
	}
	if seo.Author == "" {
		seo.Author = Me.FullName
	}
	if seo.Image == "" {
		seo.Image, seo.ImageAlt, seo.ImageWidth, seo.ImageHeight = defaultImage, defaultImageAlt, defaultImageWidth, defaultImageHeight
	}
	if seo.ImageAlt == "" {
		seo.ImageAlt = seo.Title
	}
	if seo.URL == "" {
		seo.URL = SiteURL + options.ActivePathname
	}
	if seo.Type == "" {
		seo.Type = "website"
	}
	if strings.HasPrefix(options.ActivePathname, "/admin") {
		seo.NoIndex = true
	}

	now := options.Now
	if now.IsZero() {
		now = time.Now()
	}
	styleVersion := options.StyleVersion
	if styleVersion == "" {
		styleVersion = options.CommitHash
	}

	language := options.Language
	if language == "" {
		language = "en"
	}

	return PageData{
		Title:    seo.Title,
		Language: language,
		SEO:      seo,
		Footer: Footer{
			Year:       now.Year(),
			CommitHash: options.CommitHash,
			GitRepoID:  options.GitRepoID,
			Version:    options.Version,
		},
		NavItems:      NavItems(options.ActivePathname),
		StyleVersion:  styleVersion,
		HotReload:     options.HotReload,
		HomeIsActive:  options.ActivePathname == "/",
		AdminScripts:  strings.HasPrefix(options.ActivePathname, "/admin"),
		SearchScripts: options.ActivePathname == "/blog" || strings.HasPrefix(options.ActivePathname, "/admin"),
		PostScripts: strings.HasPrefix(options.ActivePathname, "/blog/") ||
			strings.HasPrefix(options.ActivePathname, "/admin/blogposts/"),
	}
}

type HomePageData struct {
	PageData
	Mail         string
	CV           string
	Resume       string
	Projects     []ProjectView
	ProjectCount int
	Posts        []PostView
}

type NotFoundPageData struct {
	PageData
	Path string
}

type AboutPageData struct {
	PageData
	Identity
	Age    int
	Career CareerProfile
}

type ProjectView struct {
	Name            string
	URL             string
	DescriptionHTML string
	AvatarURL       string
	HasAvatar       bool
	HSLColor        string
	FirstLetter     string
	LastCommitDate  string
	LastCommitTime  string
	LastCommitHash  string
	LastCommitURL   string
	LicenseLabel    string
	LicenseURL      string
}

type ProjectsPageData struct {
	PageData
	Identity
	Featured []ProjectView
	Others   []ProjectView
}

// featuredProjects names the repositories shown first, in order.
var featuredProjects = [...]string{"wren", "papier", "gui_toolkit", "opencode_native", "lutin", "shojiwm-desktop"}

// SplitProjects separates the featured projects, in their curated order, from the
// others, which keep their order. A featured project that is missing is skipped.
func SplitProjects(projects []ProjectView) (featured, others []ProjectView) {
	byName := make(map[string]ProjectView, len(projects))
	for _, project := range projects {
		byName[project.Name] = project
	}
	isFeatured := make(map[string]bool, len(featuredProjects))
	for _, name := range featuredProjects {
		if project, found := byName[name]; found {
			featured = append(featured, project)
			isFeatured[name] = true
		}
	}
	for _, project := range projects {
		if !isFeatured[project.Name] {
			others = append(others, project)
		}
	}
	return featured, others
}

type PostView struct {
	Slug          string
	Title         string
	Description   string
	Excerpt       string
	Language      string
	HTML          string
	PublishedOn   string
	CreatedOn     string
	CreatedAtTime string
	UpdatedOn     string
	UpdatedAtTime string
	TOC           []TOCItem
}

// TOCItem is one entry of a post's table of contents.
type TOCItem struct {
	Level int
	ID    string
	Title string
}

type PostYearGroup struct {
	Year  int
	Posts []PostView
}

type BlogPageData struct {
	PageData
	YearGroups []PostYearGroup
	// Query is the search of /blog?q=; empty lists every post.
	Query string
}

type PostPageData struct {
	PageData
	Post PostView
	// More lists other posts, newest first, to read next.
	More []PostView
}

// searchSummary tells how many posts a blog search found.
func searchSummary(groups []PostYearGroup, query string) string {
	count := 0
	for _, group := range groups {
		count += len(group.Posts)
	}
	switch count {
	case 0:
		return "No post matches “" + query + "”."
	case 1:
		return "1 post matches “" + query + "”."
	}
	return strconv.Itoa(count) + " posts match “" + query + "”."
}
