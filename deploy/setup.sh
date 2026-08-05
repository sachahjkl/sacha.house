#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly INSTALL_ROOT="/opt/sacha.house"
readonly STATE_DIR="/var/lib/sacha.house"
readonly DEPLOY_STATE_DIR="/var/lib/sacha.house-deploy"
readonly CONFIG_FILE="${STATE_DIR}/config.json"
readonly SERVICE_NAME="sacha.house.service"
readonly SERVICE_USER="sacha"
readonly SERVICE_GROUP="sacha"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

if (( EUID != 0 )); then
    printf 'setup must run as root\n' >&2
    exit 1
fi

for command in curl flock getent groupadd install jq realpath sha256sum systemctl tar useradd; do
    if ! command -v "$command" >/dev/null; then
        printf 'required command not found: %s\n' "$command" >&2
        exit 1
    fi
done

if ! getent group "$SERVICE_GROUP" >/dev/null; then
    groupadd --system "$SERVICE_GROUP"
fi
if ! getent passwd "$SERVICE_USER" >/dev/null; then
    useradd --system \
        --gid "$SERVICE_GROUP" \
        --home-dir "$STATE_DIR" \
        --shell /usr/sbin/nologin \
        "$SERVICE_USER"
fi

install -d -o root -g root -m 0700 "$DEPLOY_STATE_DIR"
exec 9>"${DEPLOY_STATE_DIR}/operation.lock"
flock --exclusive 9

install -d -o root -g root -m 0755 "$INSTALL_ROOT" "$INSTALL_ROOT/releases"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0700 "$STATE_DIR"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 "$STATE_DIR/data" "$STATE_DIR/data/blog"

if [[ ! -f "$CONFIG_FILE" ]]; then
    printf 'runtime configuration is required at %s\n' "$CONFIG_FILE" >&2
    exit 1
fi
if ! jq -e . "$CONFIG_FILE" >/dev/null; then
    printf 'runtime configuration is not valid JSON: %s\n' "$CONFIG_FILE" >&2
    exit 1
fi
chown "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_FILE"
chmod 0600 "$CONFIG_FILE"

webauthn_file="$(jq -r '.WEBAUTHN_CREDENTIALS_FILE // "webauthn_credentials.json"' "$CONFIG_FILE")"
paste_secrets_file="$(jq -r '.PASTE_SECRETS_FILE // "paste-secrets.json"' "$CONFIG_FILE")"
if [[ "$webauthn_file" != "webauthn_credentials.json" ]]; then
    printf 'WEBAUTHN_CREDENTIALS_FILE must be webauthn_credentials.json\n' >&2
    exit 1
fi
if [[ "$paste_secrets_file" != "paste-secrets.json" ]]; then
    printf 'PASTE_SECRETS_FILE must be paste-secrets.json\n' >&2
    exit 1
fi
if jq -e '.PASTE_ENABLED == true' "$CONFIG_FILE" >/dev/null && [[ ! -f "$STATE_DIR/$paste_secrets_file" ]]; then
    printf 'enabled paste storage requires %s\n' "$STATE_DIR/$paste_secrets_file" >&2
    exit 1
fi

for state_file in projects_cache.json webauthn_credentials.json paste-secrets.json; do
    if [[ -f "$STATE_DIR/$state_file" ]]; then
        chown "$SERVICE_USER:$SERVICE_GROUP" "$STATE_DIR/$state_file"
        chmod 0600 "$STATE_DIR/$state_file"
    fi
done
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$STATE_DIR/data/blog"

install -d -o root -g root -m 0755 /usr/local/sbin
install -o root -g root -m 0755 "$SCRIPT_DIR/update.sh" /usr/local/sbin/sacha-house-update
install -o root -g root -m 0755 "$SCRIPT_DIR/rollback.sh" /usr/local/sbin/sacha-house-rollback
install -o root -g root -m 0755 "$SCRIPT_DIR/backup.sh" /usr/local/sbin/sacha-house-backup
install -o root -g root -m 0755 "$SCRIPT_DIR/restore.sh" /usr/local/sbin/sacha-house-restore
install -o root -g root -m 0644 "$SCRIPT_DIR/sacha.house.service" /etc/systemd/system/sacha.house.service

if command -v crontab >/dev/null; then
    legacy_crontab="$(mktemp "${DEPLOY_STATE_DIR}/crontab.XXXXXXXX")"
    trap 'rm -f -- "$legacy_crontab"' EXIT
    crontab -l > "$legacy_crontab" 2>/dev/null || true
    while IFS= read -r line; do
        [[ "$line" == *"/opt/sacha.house/update.sh"* ]] || printf '%s\n' "$line"
    done < "$legacy_crontab" | crontab -
fi

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
flock --unlock 9
/usr/local/sbin/sacha-house-update
rm -f -- "$INSTALL_ROOT/update.sh" "$INSTALL_ROOT/sacha.house" "$INSTALL_ROOT/sacha.house.new" "$INSTALL_ROOT/sacha.house.bak"
rm -f -- /var/log/sacha.house-update.log

printf 'sacha.house installed; runtime state is in %s\n' "$STATE_DIR"
