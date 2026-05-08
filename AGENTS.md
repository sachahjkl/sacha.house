# AGENTS

## Repo Overview

- Main app code lives in `src/` and is written in Odin.
- HTTP helpers and the template runtime/compiler live in `lib/`.
- Templates are authored in `src/templates/*.temple.twig` and transpiled into `lib/temple/templates.odin`.
- Tailwind source lives in `styles/app.css` and the generated stylesheet is `src/static/css/style.css`.
- Static assets are embedded at compile time via `#load_directory`, so generated static files must be up to date before building.
- Blog content is filesystem-backed under `data/blog/`.

## Common Commands

- `just dev`: build and run the dev watcher.
- `just build release`: regenerate templates/CSS and build the release binary.
- `just templates`: rebuild Temple-generated template bindings.
- `bun run build:css`: rebuild `src/static/css/style.css` from Tailwind.
- `nix build .#dockerImage`: build the Docker image tarball via `dockerTools` on Linux.

## Build Notes

- If you change anything in `src/templates/`, run `just templates` before considering the change done.
- If you change anything in `styles/app.css` or Tailwind-using templates, run `bun run build:css`.
- The committed `lib/temple/templates.odin` and `src/static/css/style.css` are build inputs, not throwaway artifacts.
- The app embeds static files into the binary, so stale generated assets will ship stale output.

## Verification Notes

- After changing templates or Tailwind classes, run `just build` and commit the regenerated `lib/temple/templates.odin` and `src/static/css/style.css` outputs.
- If a change claims generated assets are up to date, verify with `git diff` after regeneration rather than trusting timestamps.
- The Nix Docker image build is expected to regenerate templates and CSS inside the derivation; the committed generated files still matter for non-Nix builds.

## WebAuthn Notes

- WebAuthn storage is configured through `WEBAUTHN_CREDENTIALS_FILE` in `config.json`.
- The passkey data file is expected to support in-place migration, so changes here should preserve older stored credentials when possible.
- Admin WebAuthn flows are split between `src/server.odin`, `src/webauthn.odin`, `src/templates/admin.temple.twig`, and `src/static/js/admin.js`.

## Deployment Notes

- GitLab CI still publishes the Linux binary artifact.
- Container images should be built from `flake.nix` via `dockerTools`, not from a handwritten Dockerfile.
- Runtime config is expected under `/data/config.json` inside the container image.
