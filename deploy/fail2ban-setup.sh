#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing fail2ban..."
apt-get update
apt-get install -y fail2ban

echo "Installing sacha.house teapot filter..."
cp "$SCRIPT_DIR/fail2ban-filter-teapot.conf" /etc/fail2ban/filter.d/sacha-house-teapot.conf

echo "Installing sacha.house teapot jail..."
cp "$SCRIPT_DIR/fail2ban-jail-teapot.conf" /etc/fail2ban/jail.d/sacha-house-teapot.conf

echo "Working around spaces in log path..."
ORIGINAL_LOG_DIR="/data/Docker/appdata/Nginx Proxy Manager/data/logs"
SYMLINK_DIR="/var/log/npm-nginx"

if [ ! -d "$ORIGINAL_LOG_DIR" ]; then
    echo "✗ Original log directory not found: $ORIGINAL_LOG_DIR"
    exit 1
fi

if [ -L "$SYMLINK_DIR" ]; then
    echo "  Symlink already exists: $SYMLINK_DIR"
elif [ -e "$SYMLINK_DIR" ]; then
    echo "✗ $SYMLINK_DIR exists but is not a symlink"
    exit 1
else
    echo "  Creating symlink: $SYMLINK_DIR -> $ORIGINAL_LOG_DIR"
    ln -s "$ORIGINAL_LOG_DIR" "$SYMLINK_DIR"
fi

if ls "$SYMLINK_DIR"/proxy-host-*_access.log 1> /dev/null 2>&1; then
    echo "✓ Found log files:"
    ls -lh "$SYMLINK_DIR"/proxy-host-*_access.log | head -3
else
    echo "✗ No log files found"
    exit 1
fi

echo "Restarting fail2ban..."
systemctl restart fail2ban

echo "Checking fail2ban status..."
fail2ban-client status sacha-house-teapot || {
    echo ""
    echo "Jail failed to start. Check /var/log/fail2ban.log for details"
    tail -20 /var/log/fail2ban.log
}

echo ""
echo "Setup complete!"
echo ""
echo "Useful commands:"
echo "  Status:       fail2ban-client status sacha-house-teapot"
echo "  Unban IP:     fail2ban-client set sacha-house-teapot unbanip <IP>"
echo "  Check banned: fail2ban-client get sacha-house-teapot banip"
echo "  View log:     tail -f /var/log/fail2ban.log"

