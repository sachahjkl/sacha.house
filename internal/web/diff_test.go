package web

import (
	"reflect"
	"strings"
	"testing"
)

func TestLineDiffKeepsChangesWithTheirContext(t *testing.T) {
	var lines []string
	for index := range 20 {
		lines = append(lines, "line "+string(rune('a'+index)))
	}
	oldText := strings.Join(lines, "\n")
	changed := append([]string(nil), lines...)
	changed[10] = "line k, changed"
	newText := strings.Join(changed, "\r\n") + "\r\n"

	hunks := LineDiff(oldText, newText)
	if len(hunks) != 1 || hunks[0].Skipped != 7 {
		t.Fatalf("hunks = %#v", hunks)
	}
	var kinds []string
	for _, line := range hunks[0].Lines {
		kinds = append(kinds, line.Kind)
	}
	want := []string{"same", "same", "same", "remove", "add", "same", "same", "same"}
	if !reflect.DeepEqual(kinds, want) || hunks[0].Lines[3].Text != "line k" || hunks[0].Lines[4].Text != "line k, changed" {
		t.Fatalf("lines = %#v", hunks[0].Lines)
	}
	if LineDiff("same\n", "same") != nil {
		t.Fatal("equal texts must give no hunk")
	}
}
