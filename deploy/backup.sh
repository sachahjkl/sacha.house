#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly STATE_DIR="/var/lib/sacha.house"
readonly DEPLOY_STATE_DIR="/var/lib/sacha.house-deploy"
readonly OPERATION_LOCK="${DEPLOY_STATE_DIR}/operation.lock"
readonly SERVICE_NAME="sacha.house.service"

if (( EUID != 0 )); then
    printf 'backup must run as root\n' >&2
    exit 1
fi
if (( $# != 1 )); then
    printf 'usage: %s BACKUP_FILE.tar.gz\n' "$0" >&2
    exit 2
fi

install -d -o root -g root -m 0700 "$DEPLOY_STATE_DIR"
exec 9>"$OPERATION_LOCK"
flock --exclusive 9

if [[ ! -f "$STATE_DIR/config.json" || ! -d "$STATE_DIR/data/blog" ]]; then
    printf 'runtime state is incomplete in %s\n' "$STATE_DIR" >&2
    exit 1
fi

backup_file="$(realpath -m -- "$1")"
state_path="$(realpath -m -- "$STATE_DIR")"
case "$backup_file" in
    "$state_path"|"$state_path"/*)
        printf 'backup destination must be outside %s\n' "$STATE_DIR" >&2
        exit 1
        ;;
esac
backup_name="$(basename -- "$backup_file")"
if [[ ! "$backup_name" =~ ^[A-Za-z0-9._-]+\.tar\.gz$ ]]; then
    printf 'backup filename must end in .tar.gz and use only safe characters\n' >&2
    exit 1
fi
if [[ ! -d "$(dirname -- "$backup_file")" ]]; then
    printf 'backup destination directory does not exist\n' >&2
    exit 1
fi

temporary="$(mktemp "${DEPLOY_STATE_DIR}/backup.XXXXXXXX.tar.gz")"
destination_temporary="$(mktemp --tmpdir="$(dirname -- "$backup_file")" .sacha-house-backup.XXXXXXXX)"
checksum_temporary="$(mktemp --tmpdir="$(dirname -- "$backup_file")" .sacha-house-checksum.XXXXXXXX)"
was_active=false
cleanup() {
    rm -f -- "$temporary" "$destination_temporary" "$checksum_temporary"
    if [[ "$was_active" == true ]]; then
        systemctl start "$SERVICE_NAME"
    fi
}
trap cleanup EXIT

if systemctl is-active --quiet "$SERVICE_NAME"; then
    was_active=true
    systemctl stop "$SERVICE_NAME"
fi

tar --create --gzip --file "$temporary" --directory "$STATE_DIR" .
install -o root -g root -m 0600 "$temporary" "$destination_temporary"
mv -fT -- "$destination_temporary" "$backup_file"
checksum_file="${backup_file}.sha256"
(
    cd -- "$(dirname -- "$backup_file")"
    sha256sum "$backup_name" > "$checksum_temporary"
)
chmod 0600 "$checksum_temporary"
mv -fT -- "$checksum_temporary" "$checksum_file"

printf 'backed up config.json, data/blog, and runtime JSON data to %s\n' "$backup_file"
