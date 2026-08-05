package web

import (
	"testing"
	"testing/fstest"
)

func TestLinkedInProfileLoaderLoadsStaticProfile(t *testing.T) {
	loader := FSLinkedInProfileLoader{FS: fstest.MapFS{
		"profile.json": &fstest.MapFile{Data: []byte(`{"experiences":[{"company":"Example"}],"education":[]}`)},
	}, Path: "profile.json"}
	profile, err := loader.Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if len(profile.Experiences) == 0 {
		t.Fatal("Experiences is empty")
	}
	if got, want := profile.Experiences[0].EndsOn(), "Present"; got != want {
		t.Fatalf("EndsOn() = %q, want %q", got, want)
	}
}
