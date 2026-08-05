#!/usr/bin/env bash

set -Eeuo pipefail

readonly ORIGINAL_LOG_DIR="/data/Docker/appdata/Nginx Proxy Manager/data/logs"
readonly SYMLINK_DIR="/var/log/npm-nginx"
readonly FILTER_FILE="/etc/fail2ban/filter.d/sacha-house-teapot.conf"

if [[ ! -d "$ORIGINAL_LOG_DIR" ]]; then
    printf 'Nginx Proxy Manager log directory not found: %s\n' "$ORIGINAL_LOG_DIR" >&2
    exit 1
fi
if [[ ! -L "$SYMLINK_DIR" ]]; then
    printf 'log symlink not found: %s\n' "$SYMLINK_DIR" >&2
    exit 1
fi
if [[ "$(readlink -f "$SYMLINK_DIR")" != "$(realpath "$ORIGINAL_LOG_DIR")" ]]; then
    printf 'log symlink has the wrong target: %s\n' "$SYMLINK_DIR" >&2
    exit 1
fi
if [[ ! -f "$FILTER_FILE" ]]; then
    printf 'fail2ban filter not found: %s\n' "$FILTER_FILE" >&2
    exit 1
fi

shopt -s nullglob
logs=("$SYMLINK_DIR"/proxy-host-*_access.log)
if (( ${#logs[@]} == 0 )); then
    printf 'no Nginx Proxy Manager access logs found in %s\n' "$SYMLINK_DIR" >&2
    exit 1
fi

printf 'testing %s with %s\n' "$FILTER_FILE" "${logs[0]}"
fail2ban-regex "${logs[0]}" "$FILTER_FILE"
