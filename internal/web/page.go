package web

import (
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
	{Title: "home", Pathname: "/", Icon: "🏠"},
	{Title: "projects", Pathname: "/projects", Icon: "📁"},
	{Title: "blog", Pathname: "/blog", Icon: "📝"},
	{Title: "about", Pathname: "/about", Icon: "📜"},
	{Title: "admin", Pathname: "/admin", Icon: "🔒"},
}

func NavItems(activePathname string) []NavItem {
	items := make([]NavItem, len(defaultNavItems))
	copy(items, defaultNavItems[:])

	for i := range items {
		if items[i].Pathname == "/" {
			items[i].IsActive = activePathname == "/"
		} else {
			items[i].IsActive = strings.HasPrefix(activePathname, items[i].Pathname)
		}
	}

	return items
}

type SEO struct {
	Title       string
	Description string
	Author      string
	Image       string
}

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
		seo.Image = "/favicon_shadow.png"
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
		NavItems:     NavItems(options.ActivePathname),
		StyleVersion: styleVersion,
		HotReload:    options.HotReload,
		AdminScripts: strings.HasPrefix(options.ActivePathname, "/admin"),
	}
}

type HomePageData struct {
	PageData
	Mail string
	CV   string
}

type AboutPageData struct {
	PageData
	Identity
	Age                 int
	LinkedInExperiences []LinkedInExperience
	LinkedInEducation   []LinkedInEducation
}

type ProjectView struct {
	Name            string
	URL             string
	DescriptionHTML string
	AvatarURL       string
	HasAvatar       bool
	HSLColor        string
	FirstLetter     string
}

type ProjectsPageData struct {
	PageData
	Identity
	GitLabProjects []ProjectView
	GitHubProjects []ProjectView
}

type PostView struct {
	Slug          string
	Title         string
	Excerpt       string
	HTML          string
	CreatedOn     string
	CreatedAtTime string
	UpdatedOn     string
	UpdatedAtTime string
}

type PostYearGroup struct {
	Year  int
	Posts []PostView
}

type BlogPageData struct {
	PageData
	YearGroups []PostYearGroup
}

type PostPageData struct {
	PageData
	Post PostView
}
