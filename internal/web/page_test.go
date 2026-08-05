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
