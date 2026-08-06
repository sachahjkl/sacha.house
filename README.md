# sacha.house

Personal website and filesystem-backed blog, built with Go, templ, Datastar, and Tailwind CSS.

## Architecture

- `cmd/sacha-house/` contains the server entry point.
- `internal/app/` contains HTTP routes and application assembly.
- `internal/web/` contains templ components and generated `*_templ.go` files.
- `internal/auth/`, `internal/blog/`, `internal/paste/`, and `internal/projects/` contain domain services.
- `internal/web/static/` contains embedded static assets and Datastar browser code.
- `styles/app.css` is the Tailwind source.
- `data/blog/` contains blog posts and media.

The Go binary embeds static assets. The server uses Datastar SSE responses for navigation and admin interactions.

## Requirements

Use the Nix development shell to get Go, Bun, just, watchexec, and Git:

```bash
nix develop
```

The shell installs JavaScript dependencies from `bun.lock` and creates `config.json` from the example when needed.

## Development

Start the development watcher:

```bash
just dev
```

The watcher monitors Go, templ, JavaScript, and CSS files. It regenerates assets, rebuilds, and restarts the server with `-dev`.

Run generation tasks separately when needed:

```bash
just templates
just css
```

## Build And Test

Build a release binary at `bin/release/sacha.house`:

```bash
just build release
```

Run all Go tests:

```bash
just test
```

Build the Nix package, static Linux artifact, or container image:

```bash
nix build .#default
nix build .#linuxBinary
nix build .#dockerImage
```

Nix builds a static binary with `CGO_ENABLED=0`. It injects the version and commit hash through Go linker flags.

## Configuration

Set `CONFIG_PATH` to the JSON configuration path. The default path is `config.json`.

Use `config.example.json` as the base configuration. Important fields include:

- `ADMIN_PASSWORD_HASH`: Argon2id admin password hash.
- `ADMIN_PASSWORD_PEPPER`: Secret value used for password hashing and verification.
- `WEBAUTHN_CREDENTIALS_FILE`: Writable passkey storage path.
- `WEBAUTHN_RP_ID`: WebAuthn relying-party identifier.
- `WEBAUTHN_RP_ORIGINS`: Allowed WebAuthn origins.
- `PASTE_ENABLED`: Enables encrypted GitHub Gist pastes under `/admin/pastes`.
- `PASTE_SECRETS_FILE`: Path to the Gist token and encryption keyring.
- `PASTE_MAX_BODY_BYTES`: Maximum plaintext body size from 1024 through 1048576 bytes.
- `PASTE_MAX_LIST_ITEMS`: Maximum examined Gists from 1 through 500.

`PASSWORD_SALT` is obsolete. Rename it to `ADMIN_PASSWORD_PEPPER` before deployment.

The Go password hash format differs from the Odin format. Generate a new hash with `--hash-password` before deployment.

The container uses `/data` as its writable volume. It reads `/data/config.json` through `CONFIG_PATH`.

### Encrypted Gist Paste Secrets

Create the secrets file before you enable pastes. The application never generates this file.

```json
{
  "github_gist_token": "github_pat_or_classic_token",
  "active_key_id": "2026-07",
  "keys": [
    { "id": "2026-07", "key_hex": "64-lowercase-hex-characters" }
  ]
}
```

Generate a key with `openssl rand -hex 32`. Give the GitHub token Gist read and write permission.

New pastes and edits use `active_key_id`. Add a new key and restart before you rotate existing pastes.

Keep old keys until no paste reports their key ID. Losing a key makes its encrypted pastes unrecoverable.

GitHub secret Gists are unlisted, not private. GitHub retains ciphertext and can retain old revisions.

Keep the secrets file outside the repository and image. Restrict it to the server account with mode `0600`.

## License

MIT
