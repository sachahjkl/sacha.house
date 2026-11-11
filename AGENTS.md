# AGENTS

## Repository Overview

- The application is written in Go under `cmd/` and `internal/`.
- HTTP routing and application assembly live in `internal/app/`.
- templ components live in `internal/web/*.templ`.
- Generated templ files use the `*_templ.go` suffix.
- Datastar server integration lives in Go handlers.
- Datastar browser code and other JavaScript live in `internal/web/static/js/`.
- Christmas mode lives in `static/js/christmas.js` and `static/css/christmas.css`, loaded on every public page. It switches itself on from 25 November to 5 January, by the visitor's date. Preview it with `?xmas=1` or `?xmasDate=2026-12-24` (also 2026-12-31 for the fireworks); `?xmas=0` turns it off. Everything in it is decoration, hidden from print.
- Tailwind source lives in `styles/app.css`.
- Generated CSS lives in `internal/web/static/css/style.css`.
- Static assets are embedded through `internal/web/static/embed.go`.
- Fonts are self-hosted under `internal/web/static/fonts/fira-code/`; the site calls no third-party font service.
- The projects shown first are listed in `featuredProjects` in `internal/web/page.go`.
- The career data of `/about`, `/resume`, and `/cv` lives in `internal/web/career.go`.
- Blog content is filesystem-backed under `data/blog/`.
- Mermaid diagrams are prerendered, never drawn in the browser: run `just diagrams` after editing a `mermaid` block, and commit the SVGs. A test fails when a shipped post has a diagram without its drawing. The page only reserves the room of each diagram; `static/js/post.js` inlines the SVG of the reader's scheme when the figure comes near the screen.
- Each post has a `description` in `post.json` (160 characters at most): it feeds the meta description, link previews, feeds, JSON-LD and `/llms.txt`. Without it, an excerpt is used.
- Post images get `loading="lazy"` and their width and height from the file. Prefer WebP; convert screenshots with `cwebp -lossless -z 9`.
- `data/embed.go` embeds `data/blog/` in the binary. At start, `blog.MergeSeed` merges the posts of the repository into the running data directory with a three-way merge. A new post is imported. If only the repository changed a post since the last merge, the post is replaced. If the repository and the admin both changed it, the admin version stays, the repository version is written as `post.seed.json` and `content.seed.md` in the post directory, and the start logs a warning once. The merge memory is `.seed-state.json` at the root of the blog data, outside the post directories, because `Store.Save` rebuilds a post directory.
- Encrypted Gist paste code lives in `internal/paste/` and `internal/app/paste.go`.

## Common Commands

- `just dev`: watch source files, rebuild, and run the server with `-dev`.
- `just build release`: regenerate templ and CSS, then build `bin/release/sacha.house`.
- `just templates`: run `go tool templ generate`.
- `just css`: rebuild Tailwind CSS with Bun.
- `just diagrams`: draw the Mermaid diagrams of `data/blog/*` into `assets/diagrams` (`tools/diagrams.ts`, needs Chrome or Edge; set `CHROME_PATH` if it is not found).
- `just test`: run `go test ./...`.
- `just secrets-check`: validate the encrypted production secrets without printing their values.
- `just run`: build and run the debug binary.
- `nix build .#dockerImage`: build the Linux container image.

## Build Notes

- Run `just templates` after each templ change.
- Run `just css` after each template, JavaScript, or Tailwind class change.
- Keep generated `*_templ.go` files and `internal/web/static/css/style.css` current.
- The Go binary embeds static assets at build time.
- Nix builds use `CGO_ENABLED=0` and inject version metadata with linker flags.

## Verification Notes

- Run `just build release` after template or static asset changes.
- Run `go test ./...` after Go changes.
- Run `nix build .#default` after Nix build changes.
- Run `nix build .#dockerImage` after container changes.
- Inspect generated-file changes after regeneration.

## WebAuthn Notes

- Configure passkey storage with `WEBAUTHN_CREDENTIALS_FILE`.
- Configure the relying party with `WEBAUTHN_RP_ID` and `WEBAUTHN_RP_ORIGINS`.
- Use `ADMIN_PASSWORD_PEPPER` for admin password hashing.
- WebAuthn code lives in `internal/auth/`, `internal/app/`, and `internal/web/`.
- Browser behavior lives in `internal/web/static/js/admin.js`.

## Paste Notes

- Configure paste storage with `PASTE_ENABLED` and `PASTE_SECRETS_FILE`.
- Keep the `paste-secrets.json` and encrypted Gist formats compatible with the Odin implementation.
- Keep old encryption keys available until all pastes use the active key.
- Test paste storage with an `httptest` GitHub API server.

## Deployment Notes

- GitHub Actions builds the application, static Linux binary, and Docker image.
- Build container images from `flake.nix` with `dockerTools`.
- The container reads runtime configuration from `/data/config.json`.
- The homelab consumes the application through a generic modular service declared in `nixconfig`.
- SecretSpec declarations live in `secretspec.toml`.
- Encrypted production values live in `secrets/sacha-house/production.yaml`.
- The NixOS service passes the age identity through a systemd credential.
