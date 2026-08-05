package web

import (
	"testing"
	"time"
)

func TestFormatDateUsesEuropeParis(t *testing.T) {
	value := time.Date(2026, time.January, 1, 23, 30, 0, 0, time.UTC)
	if got, want := FormatDate(value), "02/01/2026"; got != want {
		t.Fatalf("FormatDate() = %q, want %q", got, want)
	}
	if got, want := FormatTime(value), "00:30:00"; got != want {
		t.Fatalf("FormatTime() = %q, want %q", got, want)
	}
}

func TestFormatTimeUsesParisDaylightSavingTime(t *testing.T) {
	value := time.Date(2026, time.July, 1, 12, 0, 0, 0, time.UTC)
	if got, want := FormatTime(value), "14:00:00"; got != want {
		t.Fatalf("FormatTime() = %q, want %q", got, want)
	}
}

func TestFormatDateZeroIsPresent(t *testing.T) {
	if got, want := FormatDate(time.Time{}), "Present"; got != want {
		t.Fatalf("FormatDate() = %q, want %q", got, want)
	}
}
