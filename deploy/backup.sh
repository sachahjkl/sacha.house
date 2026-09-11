#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

if (( EUID != 0 )); then
  printf 'backup must run as root\n' >&2
  exit 1
fi
if (( $# != 2 )); then
  printf 'usage: %s {staging|production} BACKUP_FILE.tar.gz\n' "$0" >&2
  exit 2
fi
if [[ "$1" != "staging" && "$1" != "production" ]]; then
  printf 'namespace must be staging or production\n' >&2
  exit 2
fi

namespace="$1"
backup_file="$(realpath -m -- "$2")"
backup_name="$(basename -- "$backup_file")"
volume_name="sacha-house-${namespace}-data"

if [[ ! "$backup_name" =~ ^[A-Za-z0-9._-]+\.tar\.gz$ ]]; then
  printf 'backup filename must end in .tar.gz and use only safe characters\n' >&2
  exit 1
fi
if [[ ! -d "$(dirname -- "$backup_file")" ]]; then
  printf 'backup destination directory does not exist\n' >&2
  exit 1
fi

volume_path="$(nomad volume status -namespace "$namespace" -json "$volume_name" | jq -r .HostPath)"
case "$volume_path" in
  /data/Services/nomad/volumes/*) ;;
  *)
    printf 'Nomad returned an unexpected volume path\n' >&2
    exit 1
    ;;
esac
if [[ ! -d "$volume_path/data/blog" ]]; then
  printf 'runtime state is incomplete in %s\n' "$volume_path" >&2
  exit 1
fi

install -d -o root -g root -m 0700 /run/lock
exec 9>"/run/lock/sacha-house-${namespace}.lock"
flock --exclusive 9

temporary="$(mktemp --tmpdir="$(dirname -- "$backup_file")" .sacha-house-backup.XXXXXXXX)"
checksum_temporary="$(mktemp --tmpdir="$(dirname -- "$backup_file")" .sacha-house-checksum.XXXXXXXX)"
trap 'rm -f -- "$temporary" "$checksum_temporary"' EXIT

tar --create --gzip --file "$temporary" --directory "$volume_path" --exclude='./backups' .
install -o root -g root -m 0600 "$temporary" "$backup_file"
(
  cd -- "$(dirname -- "$backup_file")"
  sha256sum "$backup_name" >"$checksum_temporary"
)
chmod 0600 "$checksum_temporary"
mv -fT -- "$checksum_temporary" "${backup_file}.sha256"

printf 'backed up %s to %s\n' "$volume_name" "$backup_file"
