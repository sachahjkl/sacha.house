package web

import "testing"

func TestNavItemsActivePath(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		activeItem string
	}{
		{name: "root", path: "/", activeItem: ""},
		{name: "section", path: "/projects", activeItem: "projects"},
		{name: "nested route", path: "/blog/an-article", activeItem: "blog"},
		{name: "resume", path: "/resume", activeItem: "résumé"},
		{name: "full CV", path: "/cv", activeItem: "résumé"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			items := NavItems(test.path)
			for _, item := range items {
				if item.IsActive != (item.Title == test.activeItem) {
					t.Errorf("item %q active = %t, want %t", item.Title, item.IsActive, item.Title == test.activeItem)
				}
			}
		})
	}
}

func TestNavItemsReturnsIndependentSlices(t *testing.T) {
	first := NavItems("/blog")
	first[0].Title = "changed"

	second := NavItems("/")
	if second[0].Title != "projects" {
		t.Fatalf("default item was mutated: got %q", second[0].Title)
	}
}

func TestNewPageDataDefaultsLanguageToEnglish(t *testing.T) {
	data := NewPageData(PageOptions{})
	if data.Language != "en" {
		t.Fatalf("Language = %q, want en", data.Language)
	}
}

func TestItalicExperienceIsFullCVOnly(t *testing.T) {
	for _, language := range []string{"fr", "en"} {
		profile := Career(language)
		found := false
		for _, experience := range profile.Experiences {
			if experience.Company != "Italic" {
				continue
			}
			found = true
			if !experience.FullOnly {
				t.Fatalf("Italic experience is not full CV only for %q", language)
			}
		}
		if !found {
			t.Fatalf("Italic experience is missing for %q", language)
		}
	}
}

func TestNavLeavesAdminOutOfThePublicNavigation(t *testing.T) {
	for _, item := range NavItems("/") {
		if item.Pathname == "/admin" {
			t.Fatal("admin is in the main navigation")
		}
	}
}

func TestSplitProjectsKeepsCuratedAndCommitOrder(t *testing.T) {
	featured, others := SplitProjects([]ProjectView{
		{Name: "dotfiles"}, {Name: "gui_toolkit"}, {Name: "nixconfig"}, {Name: "wren"},
	})
	if len(featured) != 2 || featured[0].Name != "wren" || featured[1].Name != "gui_toolkit" {
		t.Fatalf("featured = %+v", featured)
	}
	if len(others) != 2 || others[0].Name != "dotfiles" || others[1].Name != "nixconfig" {
		t.Fatalf("others = %+v", others)
	}
}

func TestCareerBackLinkFollowsTheLanguage(t *testing.T) {
	if got := Career("fr").BackLabel; got != "← retour à sacha.house" {
		t.Fatalf("fr BackLabel = %q", got)
	}
	if got := Career("en").BackLabel; got != "← back to sacha.house" {
		t.Fatalf("en BackLabel = %q", got)
	}
}

func TestPageDataDescribesThePageForSharing(t *testing.T) {
	data := NewPageData(PageOptions{ActivePathname: "/blog", Language: "fr"})
	if data.SEO.URL != "https://sacha.house/blog" || data.Locale() != "fr_FR" {
		t.Fatalf("URL = %q, locale = %q", data.SEO.URL, data.Locale())
	}
	if data.SEO.Image != "https://sacha.house/static/og.png" {
		t.Fatalf("Image = %q", data.SEO.Image)
	}
	if !NewPageData(PageOptions{ActivePathname: "/admin/login"}).SEO.NoIndex {
		t.Fatal("admin pages are indexable")
	}
}
