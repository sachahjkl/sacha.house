package web

import "testing"

func TestNavItemsActivePath(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		activeItem string
	}{
		{name: "root", path: "/", activeItem: "home"},
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
	if second[0].Title != "home" {
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
