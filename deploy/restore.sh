#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly STATE_DIR="/var/lib/sacha.house"
readonly SERVICE_USER="sacha"
readonly SERVICE_GROUP="sacha"
readonly SERVICE_NAME="sacha.house.service"
readonly HEALTH_URL="http://127.0.0.1:6969/ping"

if (( EUID != 0 )); then
    printf 'restore must run as root\n' >&2
    exit 1
fi
if (( $# < 1 || $# > 2 )); then
    printf 'usage: %s BACKUP_FILE.tar.gz [BACKUP_FILE.sha256]\n' "$0" >&2
    exit 2
fi

archive="$(realpath -- "$1")"
checksum="$(realpath -- "${2:-$1.sha256}")"
read -r expected_hash expected_name < "$checksum"
expected_name="${expected_name#\*}"
if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || [[ "$expected_name" != "$(basename -- "$archive")" ]]; then
    printf 'backup checksum has an invalid format\n' >&2
    exit 1
fi
actual_hash="$(sha256sum "$archive")"
actual_hash="${actual_hash%% *}"
if [[ "$actual_hash" != "$expected_hash" ]]; then
    printf 'backup checksum verification failed\n' >&2
    exit 1
fi

while IFS= read -r entry; do
    case "$entry" in
        /*|../*|*/../*|*/..)
            printf 'backup contains an unsafe path\n' >&2
            exit 1
            ;;
    esac
done < <(tar --list --gzip --file "$archive")

state_parent="$(dirname -- "$STATE_DIR")"
staging="${state_parent}/.sacha.house.restore.$$"
old_state="${state_parent}/.sacha.house.pre-restore.$$"
restore_failed="${state_parent}/.sacha.house.failed-restore.$$"
was_active=false
switched=false
cleanup() {
    rm -rf -- "$staging"
    if [[ "$switched" == false && "$was_active" == true ]]; then
        systemctl start "$SERVICE_NAME"
    fi
}
trap cleanup EXIT

install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0700 "$staging"
runuser --user "$SERVICE_USER" -- tar \
    --extract --gzip --no-same-owner --no-same-permissions \
    --file "$archive" --directory "$staging"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    was_active=true
    systemctl stop "$SERVICE_NAME"
fi

mv -- "$STATE_DIR" "$old_state"
mv -- "$staging" "$STATE_DIR"
switched=true

wait_until_healthy() {
    local attempt
    for attempt in {1..30}; do
        if systemctl is-active --quiet "$SERVICE_NAME" && \
           curl --fail --silent --show-error --max-time 2 "$HEALTH_URL" >/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

if [[ "$was_active" == false ]] || (systemctl start "$SERVICE_NAME" && wait_until_healthy); then
    rm -rf -- "$old_state"
    printf 'restored verified state from %s\n' "$archive"
    exit 0
fi

printf 'restored state failed its health check; rolling back data\n' >&2
systemctl stop "$SERVICE_NAME" || true
mv -- "$STATE_DIR" "$restore_failed"
mv -- "$old_state" "$STATE_DIR"
rm -rf -- "$restore_failed"
if [[ "$was_active" == true ]]; then
    systemctl start "$SERVICE_NAME"
    wait_until_healthy || printf 'original state failed its health check after rollback\n' >&2
fi
exit 1
