#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly INSTALL_ROOT="/opt/sacha.house"
readonly RELEASES_DIR="${INSTALL_ROOT}/releases"
readonly CURRENT_LINK="${INSTALL_ROOT}/current"
readonly PREVIOUS_LINK="${INSTALL_ROOT}/previous"
readonly DEPLOY_STATE_DIR="/var/lib/sacha.house-deploy"
readonly OPERATION_LOCK="${DEPLOY_STATE_DIR}/operation.lock"
readonly SERVICE_NAME="sacha.house.service"
readonly ARTIFACT_NAME="sacha.house-linux-amd64"
readonly RELEASE_API="https://gitlab.com/api/v4/projects/sachahjkl%2Fsacha.house/releases/permalink/latest"
readonly HEALTH_URL="http://127.0.0.1:6969/ping"

if (( EUID != 0 )); then
    printf 'update must run as root\n' >&2
    exit 1
fi

install -d -o root -g root -m 0755 "$INSTALL_ROOT" "$RELEASES_DIR"
install -d -o root -g root -m 0700 "$DEPLOY_STATE_DIR"
exec 9>"$OPERATION_LOCK"
flock --exclusive 9
work_dir="$(mktemp -d "${DEPLOY_STATE_DIR}/update.XXXXXXXX")"
current_temp="${CURRENT_LINK}.new.$$"
previous_temp="${PREVIOUS_LINK}.new.$$"
trap 'rm -rf -- "$work_dir"; rm -f -- "$current_temp" "$previous_temp"' EXIT

curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$RELEASE_API" --output "$work_dir/release.json"

binary_url="$(jq -er '.assets.links | first(.[] | select(.name == "sacha.house Linux AMD64 Binary")) | .direct_asset_url // .url' "$work_dir/release.json")"
checksum_url="$(jq -er '.assets.links | first(.[] | select(.name == "sacha.house Linux AMD64 SHA256")) | .direct_asset_url // .url' "$work_dir/release.json")"
release_version="$(jq -er '.tag_name' "$work_dir/release.json")"

curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$binary_url" --output "$work_dir/$ARTIFACT_NAME"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$checksum_url" --output "$work_dir/$ARTIFACT_NAME.sha256"

read -r expected_hash expected_name < "$work_dir/$ARTIFACT_NAME.sha256"
expected_name="${expected_name#\*}"
if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || [[ "$expected_name" != "$ARTIFACT_NAME" ]]; then
    printf 'release checksum has an invalid format\n' >&2
    exit 1
fi
actual_hash="$(sha256sum "$work_dir/$ARTIFACT_NAME")"
actual_hash="${actual_hash%% *}"
if [[ "$actual_hash" != "$expected_hash" ]]; then
    printf 'release checksum verification failed\n' >&2
    exit 1
fi

chmod 0755 "$work_dir/$ARTIFACT_NAME"
binary_version="$("$work_dir/$ARTIFACT_NAME" --version)"
if [[ "$binary_version" != "$release_version" ]]; then
    printf 'release tag does not match the binary version\n' >&2
    exit 1
fi

release_dir="${RELEASES_DIR}/${actual_hash}"
if [[ -e "$release_dir" && ! -d "$release_dir" ]]; then
    printf 'release path is not a directory: %s\n' "$release_dir" >&2
    exit 1
fi
install -d -o root -g root -m 0755 "$release_dir"
if [[ ! -f "$release_dir/sacha.house" ]]; then
    install -o root -g root -m 0755 "$work_dir/$ARTIFACT_NAME" "$release_dir/sacha.house"
fi
installed_hash="$(sha256sum "$release_dir/sacha.house")"
installed_hash="${installed_hash%% *}"
if [[ "$installed_hash" != "$actual_hash" ]]; then
    printf 'installed release failed checksum verification\n' >&2
    exit 1
fi

atomic_switch() {
    local link_path="$1"
    local link_temp="$2"
    local target="$3"
    ln -s "$target" "$link_temp"
    mv -Tf "$link_temp" "$link_path"
}

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

old_target=""
if [[ -L "$CURRENT_LINK" ]]; then
    old_target="$(readlink -f "$CURRENT_LINK")"
fi
if [[ "$old_target" == "$release_dir" ]]; then
    if systemctl restart "$SERVICE_NAME" && wait_until_healthy; then
        printf 'verified active release %s\n' "$release_version"
        exit 0
    fi
    printf 'active release failed its health check\n' >&2
    exit 1
fi

atomic_switch "$CURRENT_LINK" "$current_temp" "$release_dir"
if systemctl restart "$SERVICE_NAME" && wait_until_healthy; then
    if [[ -n "$old_target" && -x "$old_target/sacha.house" ]]; then
        atomic_switch "$PREVIOUS_LINK" "$previous_temp" "$old_target"
    fi
    printf 'activated verified release %s\n' "$release_version"
    exit 0
fi

printf 'new release failed its health check; rolling back\n' >&2
if [[ -n "$old_target" && -x "$old_target/sacha.house" ]]; then
    atomic_switch "$CURRENT_LINK" "$current_temp" "$old_target"
    systemctl restart "$SERVICE_NAME"
    if wait_until_healthy; then
        printf 'rollback restored %s\n' "$old_target" >&2
    else
        printf 'rollback target failed its health check\n' >&2
    fi
else
    rm -f -- "$CURRENT_LINK"
    systemctl stop "$SERVICE_NAME" || true
    printf 'no previous release was available\n' >&2
fi
exit 1
