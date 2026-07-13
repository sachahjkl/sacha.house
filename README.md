# sacha.house

The personal website of Sacha Froment, built with **Odin**.

## Overview

The application is a self-contained Odin web server with an explicit `App_State` lifecycle, a filesystem-backed blog CMS, passkey/password administration, and compile-time embedded assets.

### Key Features

* **Odin backend** built on the bundled `odin-http` router and middleware.
* **Temple templates** transpiled from Twig-like source into escaped, typed Odin renderers.
* **Local blog CMS** stored under `data/blog/` and managed from `/admin`.
* **Encrypted Gist pastes** managed from `/admin/pastes`; plaintext is encrypted server-side with versioned XChaCha20-Poly1305 before it reaches GitHub.
* **WebAuthn and password authentication** with bounded one-time challenges, server-side sessions, CSRF protection, and atomic credential storage.
* **GitHub/GitLab project aggregation** over verified HTTPS with a last-good local cache.
* **Hot reloading** through the custom `tools/dev-watcher` utility on Windows and Linux.
* **Tailwind CSS** regenerated together with Temple bindings for local and Nix builds.

## Prerequisites

*   [Odin](https://odin-lang.org/) (latest version recommended)
*   [Bun](https://bun.sh/) (for Tailwind CSS and JS dependencies)
*   [`just`](https://github.com/casey/just) command runner
*   `cl` (MSVC) on Windows or `gcc`/`clang` on Linux

On Debian-based Linux hosts, install the native build/runtime dependencies first:

```bash
sudo apt install clang just libssl-dev libbacktrace-dev libcmark-dev
```

`vendor:commonmark` links against the system `libcmark` on Linux, so Linux binaries should be built on the same distro family they will run on. The GitLab CI pipeline uses `debian:bookworm` for this reason.

## Development

To start the development server with **hot reloading**:

```bash
just dev
```

This command:
1.  Builds and runs the `tools/dev-watcher` utility.
2.  Watches `src/` and `lib/` for changes.
3.  Recompiles the project and restarts the server automatically.
4.  Injects a hot-reload script into the browser to refresh the page on server restart.

## Build

To build for production:

```bash
just build release
```

This generates the binary at `bin/release/x86_64/sacha.house.exe` (arch directory depends on host architecture).

For Linux deployment, build on the target distro family instead of shipping a binary compiled against a different system `libcmark` soname.

## Configuration

The application loads JSON configuration from `CONFIG_PATH`, or `config.json` by default. Start from `config.example.json`.

Important fields:

* `GITHUB_BEARER_TOKEN` and `GITLAB_BEARER_TOKEN`: optional repository-project API credentials.
* `ADMIN_PASSWORD_HASH` and `PASSWORD_SALT`: Argon2id admin password verifier and secret pepper.
* `WEBAUTHN_CREDENTIALS_FILE`, `WEBAUTHN_RP_ID`, and `WEBAUTHN_ORIGIN`: passkey persistence and relying-party identity.
* `TRUST_PROXY_HTTPS`: emit HSTS and Secure cookies only when the trusted reverse proxy guarantees HTTPS.
* `PASTE_ENABLED`, `PASTE_SECRETS_FILE`, `PASTE_MAX_BODY_BYTES`, and `PASTE_MAX_LIST_ITEMS`: encrypted Gist paste feature, secrets file, and bounds.

When upgrading an existing configuration, merge every field from `config.example.json`. In particular, HTTPS deployments behind a trusted reverse proxy need `TRUST_PROXY_HTTPS: true`; without it, the admin login's same-origin check rejects browser HTTPS requests. Configure `WEBAUTHN_RP_ID` and `WEBAUTHN_ORIGIN` for the public hostname as well.

The password login requires both a stable `PASSWORD_SALT` and its matching Argon2id `ADMIN_PASSWORD_HASH`. To check a password against the active configuration without changing it:

```bash
CONFIG_PATH=/path/to/config.json sacha.house --verify-password='password'
```

The password is passed as a command-line argument, so prefer a temporary shell with an unrecorded history and do not use this command on a multi-user host.

### Encrypted Gist paste secrets

`PASTE_ENABLED` defaults to `false`. When enabling it, create the file named by `PASTE_SECRETS_FILE` yourself; the application never generates it because it contains the Gist token and encryption keys. Keep it outside the repository, image, and Nix store:

```json
{
  "github_gist_token": "github_pat_or_classic_token",
  "active_key_id": "2026-07",
  "keys": [
    { "id": "2026-07", "key_hex": "64-lowercase-hex-characters" }
  ]
}
```

Generate a 32-byte key with `openssl rand -hex 32`. The GitHub token must have Gists read/write permission; a classic token needs the `gist` scope. Use a dedicated token rather than the project-fetching token.

New pastes and edits use `active_key_id`. To rotate keys, add a new key, make it active, restart, then use the admin rotation action. Keep every old key until no paste reports that key ID. GitHub Gists marked secret are unlisted, not private: GitHub still exposes owner, timestamps, size, revisions, and ciphertext. Old ciphertext also remains in Gist revision history. The server sees plaintext while processing requests.

Protect both the token and every encryption key with mode `0600`. Losing an old key makes Gists encrypted with it unrecoverable.

## Deployment and recovery

The hardened systemd unit runs as an unprivileged user, keeps releases root-owned under `/opt/sacha.house`, and writes runtime state only under `/var/lib/sacha.house`. Configuration and paste secrets are mounted read-only.

For the NixOS module, set `services.sacha-house.configFile` to a runtime path. For this homelab's wrapper, it is `${dataDir}/config.json`, which defaults to `/data/Services/sacha.house/config.json`. Keep writable state, including `WEBAUTHN_CREDENTIALS_FILE`, under `dataDir`:

```json
{
  "WEBAUTHN_CREDENTIALS_FILE": "/data/Services/sacha.house/webauthn-credentials.json",
  "WEBAUTHN_RP_ID": "sacha.house",
  "WEBAUTHN_ORIGIN": "https://sacha.house",
  "TRUST_PROXY_HTTPS": true,
  "PASTE_ENABLED": false
}
```

If pastes are enabled, point `PASTE_SECRETS_FILE` at the provisioned secret under `dataDir` or configure the module's read-only secret mount. The container uses UID/GID `10001`, `/data` for writable state, `/config/config.json` for configuration, and `/run/secrets/paste-secrets.json` for paste credentials.

Operational scripts:

```bash
sudo deploy/backup.sh /secure-backups/sacha.house-state.tar.gz
sudo deploy/restore.sh /secure-backups/sacha.house-state.tar.gz
sudo deploy/rollback.sh
```

The state backup includes the blog, passkeys, and caches. It intentionally excludes `/etc/sacha.house/config.json`, the GitHub token, and paste encryption keys; back those secrets up separately in an encrypted secret store. Restore verifies the archive checksum and rolls data back if the health check fails. Release updates use hash-addressed directories and an atomic `current` symlink.

## Project Structure

*   `src/`: Main application source code.
    *   `src/templates/`: `.temple.twig` templates.
    *   `src/static/`: Static assets (images, css, js).
*   `lib/`:
    *   `odin-http/`: HTTP server library.
    *   `temple/`: Templating engine compiler and runtime.
*   `tools/`:
    *   `dev-watcher/`: Development tool for hot reloading.
    *   `blog-migrate/`: Hygraph-to-local-blog migration script.
*   `deploy/`: Deployment scripts (systemd, fail2ban).
*   `styles/`: Tailwind CSS input files.

## License

MIT
