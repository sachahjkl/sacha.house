#!/usr/bin/env bash

set -Eeuo pipefail

readonly INSTALL_ROOT="/opt/sacha.house"
readonly STATE_DIR="/var/lib/sacha.house"
readonly DEPLOY_STATE_DIR="/var/lib/sacha.house-deploy"
readonly CONFIG_DIR="/etc/sacha.house"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly SERVICE_NAME="sacha.house.service"
readonly SERVICE_USER="sacha"
readonly SERVICE_GROUP="sacha"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

if (( EUID != 0 )); then
    printf 'setup must run as root\n' >&2
    exit 1
fi

for command in curl getent groupadd install jq realpath runuser sha256sum systemctl tar useradd; do
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

install -d -o root -g root -m 0755 "$INSTALL_ROOT" "$INSTALL_ROOT/releases"
install -d -o root -g root -m 0700 "$DEPLOY_STATE_DIR"
if [[ -e "$INSTALL_ROOT/update.sh" ]]; then
    chown root:root "$INSTALL_ROOT/update.sh"
    chmod 0755 "$INSTALL_ROOT/update.sh"
fi

if command -v crontab >/dev/null; then
    legacy_crontab="$(mktemp "${DEPLOY_STATE_DIR}/crontab.XXXXXXXX")"
    trap 'rm -f -- "$legacy_crontab"' EXIT
    crontab -l > "$legacy_crontab" 2>/dev/null || true
    while IFS= read -r line; do
        [[ "$line" == *"/opt/sacha.house/update.sh"* ]] || printf '%s\n' "$line"
    done < "$legacy_crontab" | crontab -
fi
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0700 "$STATE_DIR"
install -d -o root -g "$SERVICE_GROUP" -m 0750 "$CONFIG_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
    printf 'runtime configuration is required at %s\n' "$CONFIG_FILE" >&2
    exit 1
fi
chown root:"$SERVICE_GROUP" "$CONFIG_FILE"
chmod 0640 "$CONFIG_FILE"

paste_secrets_file="$(jq -r '.PASTE_SECRETS_FILE // empty' "$CONFIG_FILE")"
if jq -e '.PASTE_ENABLED == true' "$CONFIG_FILE" >/dev/null; then
    if [[ -z "$paste_secrets_file" ]]; then
        printf 'enabled paste storage requires PASTE_SECRETS_FILE in %s\n' "$CONFIG_FILE" >&2
        exit 1
    fi
    if [[ ! -f "$paste_secrets_file" ]]; then
        printf 'enabled paste storage requires runtime secrets at %s\n' "$paste_secrets_file" >&2
        exit 1
    fi
fi

if [[ -n "$paste_secrets_file" && -f "$paste_secrets_file" ]]; then
    chown root:"$SERVICE_GROUP" "$paste_secrets_file"
    chmod 0640 "$paste_secrets_file"
fi

install -d -o root -g root -m 0755 /usr/local/sbin
install -o root -g root -m 0755 "$SCRIPT_DIR/update.sh" /usr/local/sbin/sacha-house-update
install -o root -g root -m 0755 "$SCRIPT_DIR/rollback.sh" /usr/local/sbin/sacha-house-rollback
install -o root -g root -m 0755 "$SCRIPT_DIR/backup.sh" /usr/local/sbin/sacha-house-backup
install -o root -g root -m 0755 "$SCRIPT_DIR/restore.sh" /usr/local/sbin/sacha-house-restore
install -o root -g root -m 0644 "$SCRIPT_DIR/sacha.house.service" /etc/systemd/system/sacha.house.service

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
/usr/local/sbin/sacha-house-update
rm -f -- "$INSTALL_ROOT/update.sh" "$INSTALL_ROOT/sacha.house" "$INSTALL_ROOT/sacha.house.new" "$INSTALL_ROOT/sacha.house.bak"
rm -f -- /var/log/sacha.house-update.log

printf 'sacha.house installed; runtime state is confined to %s\n' "$STATE_DIR"
