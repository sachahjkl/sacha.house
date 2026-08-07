package app

import "testing"

func TestHost(t *testing.T) {
	t.Setenv("HOST", "")
	if got := Host(); got != DefaultHost {
		t.Fatalf("Host() = %q, want %q", got, DefaultHost)
	}

	t.Setenv("HOST", " 0.0.0.0 ")
	if got := Host(); got != "0.0.0.0" {
		t.Fatalf("Host() = %q, want %q", got, "0.0.0.0")
	}
}
