# Changelog fragments

Each change that a visitor or the site owner can see is one file in this folder, in the same commit as the change.
Do not edit `CHANGELOG.md` by hand.

- Name: `<yyyymmdd-hhmmss>-<subject>.md`.
- Line 1: `type: <type>`, where the type is Added, Changed, Deprecated, Removed, Fixed or Security.
- Line 2: empty.
- Then the text of one entry. Start it with a short bold summary, then say what changed for the reader.

At a release, the fragments move into a new section of `CHANGELOG.md` with the version and the date, then they are deleted.
