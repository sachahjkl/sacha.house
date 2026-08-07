# Deployment

The deployment installs one static Go binary. Releases are stored under `/opt/sacha.house/releases` and selected with atomic symbolic links.

Runtime state is stored under `/var/lib/sacha.house`:

- `config.json`
- `data/blog/`
- `projects_cache.json`
- `webauthn_credentials.json`
- `paste-secrets.json`

The last three files can be absent until their features create or require them.

## Requirements

Install `curl`, `jq`, `tar`, `coreutils`, `util-linux`, and `systemd`. The setup script creates the `sacha` system user and group.

The GitHub release must provide these assets:

- `sacha.house-linux-amd64`
- `sacha.house-linux-amd64.sha256`

Create a tag named `v<binary-version>`. The GitHub workflow rejects a tag that does not match the binary version.

## Configuration

Create the state directory and install your configuration before setup:

```bash
sudo install -d -o root -g root -m 0755 /var/lib/sacha.house
sudo install -o root -g root -m 0600 /path/to/config.json /var/lib/sacha.house/config.json
sudo install -d -o root -g root -m 0755 /var/lib/sacha.house/data/blog
```

Use relative runtime paths in `config.json`:

```json
{
  "WEBAUTHN_CREDENTIALS_FILE": "webauthn_credentials.json",
  "WEBAUTHN_RP_ID": "sacha.house",
  "WEBAUTHN_RP_ORIGINS": ["https://sacha.house"],
  "TRUST_PROXY_HTTPS": true,
  "PASTE_SECRETS_FILE": "paste-secrets.json"
}
```

Add the other fields from `config.example.json`. Replace all example credentials before deployment.

If paste storage is enabled, install its existing secrets file before setup:

```bash
sudo install -o root -g root -m 0600 /secure/path/paste-secrets.json /var/lib/sacha.house/paste-secrets.json
```

Never commit `config.json`, `webauthn_credentials.json`, or `paste-secrets.json`. Never put real secrets in deployment scripts.

The homelab modular service resolves production secrets from `secrets/sacha-house/production.yaml` with SecretSpec 0.18.

Its init adapter passes the age identity as a protected credential. SecretSpec injects tokens and administrator credentials as environment variables.

SecretSpec materializes `PASTE_SECRETS_FILE` inside the service's private temporary directory. Keep WebAuthn credentials in the mutable state directory.

Validate the encrypted production values from a development shell:

```bash
just secrets-check
```

Copy existing blog data to `/var/lib/sacha.house/data/blog`. Copy existing cache and credential files to the state directory.

## Installation

Run setup from the repository checkout:

```bash
sudo bash deploy/setup.sh
```

Setup performs these operations:

1. Creates the service account and runtime directories.
2. Validates `config.json` and required paste secrets.
3. Installs deployment commands in `/usr/local/sbin`.
4. Installs and enables `sacha.house.service`.
5. Downloads and verifies the latest static Go binary.
6. Starts the release and verifies `http://127.0.0.1:6969/ping`.
7. Removes the obsolete binary, update script, log, and cron entry.

## Operations

Update to the latest verified GitHub release:

```bash
sudo sacha-house-update
```

Roll back to the previous verified release:

```bash
sudo sacha-house-rollback
```

Create a consistent state backup and its SHA-256 file:

```bash
sudo sacha-house-backup /secure/backups/sacha-house-$(date +%F).tar.gz
```

Restore a verified backup. The command restores the previous state if the health check fails:

```bash
sudo sacha-house-restore /secure/backups/sacha-house-2026-08-05.tar.gz
```

Update, rollback, backup, and restore use one exclusive lock. A restored service starts and passes its health check before old state deletion.

The Docker image runs as UID and GID `65532`. Give this identity write access when bind-mounting `/data`.

Inspect the service:

```bash
sudo systemctl status sacha.house.service
sudo journalctl -u sacha.house.service -f
```

## Fail2ban

The Fail2ban jail reads Nginx Proxy Manager access logs through `/var/log/npm-nginx`.

Install or refresh the jail:

```bash
sudo bash deploy/fail2ban-setup.sh
```

Test the installed filter against the first matching access log:

```bash
sudo bash deploy/fail2ban-test.sh
```
