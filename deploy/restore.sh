#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

if (( EUID != 0 )); then
  printf 'restore must run as root\n' >&2
  exit 1
fi
if (( $# < 2 || $# > 3 )); then
  printf 'usage: %s {staging|production} BACKUP_FILE.tar.gz [BACKUP_FILE.sha256]\n' "$0" >&2
  exit 2
fi
if [[ "$1" != "staging" && "$1" != "production" ]]; then
  printf 'namespace must be staging or production\n' >&2
  exit 2
fi

namespace="$1"
archive="$(realpath -- "$2")"
checksum="$(realpath -- "${3:-$2.sha256}")"
volume_name="sacha-house-${namespace}-data"

read -r expected_hash expected_name <"$checksum"
expected_name="${expected_name#\*}"
if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || [[ "$expected_name" != "$(basename -- "$archive")" ]]; then
  printf 'backup checksum has an invalid format\n' >&2
  exit 1
fi
actual_hash="$(sha256sum "$archive")"
if [[ "${actual_hash%% *}" != "$expected_hash" ]]; then
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
while IFS= read -r metadata; do
  case "${metadata:0:1}" in
    -|d) ;;
    *)
      printf 'backup contains a link or special file\n' >&2
      exit 1
      ;;
  esac
done < <(tar --list --verbose --gzip --file "$archive")

job_status="$(nomad job status -namespace "$namespace" -json sacha-house 2>/dev/null | jq -r '.[0].Status' || true)"
if [[ -n "$job_status" && "$job_status" != "dead" ]]; then
  printf 'stop the %s sacha-house Nomad job before restoration\n' "$namespace" >&2
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

install -d -o root -g root -m 0700 /run/lock
exec 9>"/run/lock/sacha-house-${namespace}.lock"
flock --exclusive 9

staging="$(mktemp -d "$(dirname -- "$volume_path")/.sacha-house-restore.XXXXXXXX")"
rollback="$(mktemp -d "$(dirname -- "$volume_path")/.sacha-house-rollback.XXXXXXXX")"
cleanup() {
  rm -rf -- "$staging" "$rollback"
}
trap cleanup EXIT

tar --extract --gzip --no-same-owner --no-same-permissions --file "$archive" --directory "$staging"
if [[ ! -d "$staging/data/blog" ]]; then
  printf 'backup does not contain the required blog data\n' >&2
  exit 1
fi

cp -a -- "$volume_path/." "$rollback/"
find "$volume_path" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
if ! cp -a -- "$staging/." "$volume_path/"; then
  find "$volume_path" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  cp -a -- "$rollback/." "$volume_path/"
  printf 'restore failed and the previous state was restored\n' >&2
  exit 1
fi
chown -R 65532:65532 "$volume_path"
chmod 0700 "$volume_path"

printf 'restored %s from %s; deploy the validated image to check application health\n' "$volume_name" "$archive"
