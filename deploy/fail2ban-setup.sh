#!/usr/bin/env bash

set -Eeuo pipefail

readonly ORIGINAL_LOG_DIR="/data/Docker/appdata/Nginx Proxy Manager/data/logs"
readonly SYMLINK_DIR="/var/log/npm-nginx"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

if (( EUID != 0 )); then
    printf 'fail2ban setup must run as root\n' >&2
    exit 1
fi
if [[ ! -d "$ORIGINAL_LOG_DIR" ]]; then
    printf 'Nginx Proxy Manager log directory not found: %s\n' "$ORIGINAL_LOG_DIR" >&2
    exit 1
fi

apt-get update
apt-get install -y fail2ban
install -o root -g root -m 0644 \
    "$SCRIPT_DIR/fail2ban-filter-teapot.conf" \
    /etc/fail2ban/filter.d/sacha-house-teapot.conf
install -o root -g root -m 0644 \
    "$SCRIPT_DIR/fail2ban-jail-teapot.conf" \
    /etc/fail2ban/jail.d/sacha-house-teapot.conf

if [[ -L "$SYMLINK_DIR" ]]; then
    if [[ "$(readlink -f "$SYMLINK_DIR")" != "$(realpath "$ORIGINAL_LOG_DIR")" ]]; then
        printf 'existing log symlink has the wrong target: %s\n' "$SYMLINK_DIR" >&2
        exit 1
    fi
elif [[ -e "$SYMLINK_DIR" ]]; then
    printf 'log path exists and is not a symlink: %s\n' "$SYMLINK_DIR" >&2
    exit 1
else
    ln -s "$ORIGINAL_LOG_DIR" "$SYMLINK_DIR"
fi

shopt -s nullglob
logs=("$SYMLINK_DIR"/proxy-host-*_access.log)
if (( ${#logs[@]} == 0 )); then
    printf 'no Nginx Proxy Manager access logs found in %s\n' "$SYMLINK_DIR" >&2
    exit 1
fi

systemctl restart fail2ban
fail2ban-client status sacha-house-teapot
printf 'installed and started the sacha-house-teapot jail\n'
