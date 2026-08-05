#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly INSTALL_ROOT="/opt/sacha.house"
readonly DEPLOY_STATE_DIR="/var/lib/sacha.house-deploy"
readonly OPERATION_LOCK="${DEPLOY_STATE_DIR}/operation.lock"
readonly CURRENT_LINK="${INSTALL_ROOT}/current"
readonly PREVIOUS_LINK="${INSTALL_ROOT}/previous"
readonly SERVICE_NAME="sacha.house.service"
readonly HEALTH_URL="http://127.0.0.1:6969/ping"

if (( EUID != 0 )); then
    printf 'rollback must run as root\n' >&2
    exit 1
fi

install -d -o root -g root -m 0700 "$DEPLOY_STATE_DIR"
exec 9>"$OPERATION_LOCK"
flock --exclusive 9

if [[ ! -L "$CURRENT_LINK" || ! -L "$PREVIOUS_LINK" ]]; then
    printf 'both current and previous releases are required for rollback\n' >&2
    exit 1
fi

current_target="$(readlink -f "$CURRENT_LINK")"
rollback_target="$(readlink -f "$PREVIOUS_LINK")"
if [[ ! -x "$current_target/sacha.house" || ! -x "$rollback_target/sacha.house" ]]; then
    printf 'release links do not point to executable releases\n' >&2
    exit 1
fi

atomic_switch() {
    local link_path="$1"
    local target="$2"
    local temporary="${link_path}.new.$$"
    trap 'rm -f -- "$temporary"' RETURN
    ln -s "$target" "$temporary"
    mv -Tf "$temporary" "$link_path"
    trap - RETURN
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

atomic_switch "$CURRENT_LINK" "$rollback_target"
if systemctl restart "$SERVICE_NAME" && wait_until_healthy; then
    atomic_switch "$PREVIOUS_LINK" "$current_target"
    printf 'rolled back to %s\n' "$rollback_target"
    exit 0
fi

printf 'rollback target failed its health check; restoring current release\n' >&2
atomic_switch "$CURRENT_LINK" "$current_target"
systemctl restart "$SERVICE_NAME"
wait_until_healthy || printf 'restored release also failed its health check\n' >&2
exit 1
