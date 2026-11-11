package web

import (
	"strings"

	"github.com/sergi/go-diff/diffmatchpatch"
)

// DiffLine is one line of a line diff.
type DiffLine struct {
	// Kind is "same", "add" (only in the new text) or "remove" (only in the old text).
	Kind string
	Text string
}

// DiffHunk is a run of changed lines with their context. Skipped counts the unchanged lines before it.
type DiffHunk struct {
	Skipped int
	Lines   []DiffLine
}

// diffContext is how many unchanged lines a hunk shows around a change.
const diffContext = 3

// LineDiff compares two texts line by line and keeps the changes with diffContext lines around them. It returns
// no hunk when the texts are equal.
func LineDiff(oldText, newText string) []DiffHunk {
	matcher := diffmatchpatch.New()
	oldRunes, newRunes, lines := matcher.DiffLinesToRunes(withFinalNewline(oldText), withFinalNewline(newText))
	diffs := matcher.DiffCharsToLines(matcher.DiffMainRunes(oldRunes, newRunes, false), lines)

	var all []DiffLine
	for _, diff := range diffs {
		kind := "same"
		switch diff.Type {
		case diffmatchpatch.DiffInsert:
			kind = "add"
		case diffmatchpatch.DiffDelete:
			kind = "remove"
		}
		for _, line := range strings.SplitAfter(diff.Text, "\n") {
			if line != "" {
				all = append(all, DiffLine{Kind: kind, Text: strings.TrimSuffix(line, "\n")})
			}
		}
	}

	// Keep the lines that are at most diffContext lines away from a change.
	keep := make([]bool, len(all))
	for index, line := range all {
		if line.Kind == "same" {
			continue
		}
		for near := max(0, index-diffContext); near <= min(len(all)-1, index+diffContext); near++ {
			keep[near] = true
		}
	}
	var hunks []DiffHunk
	skipped := 0
	for index, line := range all {
		if !keep[index] {
			skipped++
			continue
		}
		if index == 0 || !keep[index-1] {
			hunks = append(hunks, DiffHunk{Skipped: skipped})
			skipped = 0
		}
		hunks[len(hunks)-1].Lines = append(hunks[len(hunks)-1].Lines, line)
	}
	return hunks
}

func withFinalNewline(text string) string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	if text != "" && !strings.HasSuffix(text, "\n") {
		text += "\n"
	}
	return text
}

func diffSign(kind string) string {
	switch kind {
	case "add":
		return "+"
	case "remove":
		return "−"
	}
	return " "
}
