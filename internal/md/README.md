# sacha.house intent

This folder records the intent of the site, as <https://srcmd.org> describes: the purpose, the design decisions, the
refused alternatives and the subtle points. The operating notes stay in `AGENTS.md`.

## Overview

The site is one Go binary. templ renders the pages, Datastar adds progressive navigation, and the blog is files on disk.

## Subtleties

- The career pages (`/resume`, `/cv`) default to English, because most readers are recruiters who read English.
  `?lang=fr` gives the French version. The data of both versions lives in `internal/web/career.go`.

## File Index
