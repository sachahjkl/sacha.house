#!/bin/bash

set -e

INSTALL_DIR="/opt/sacha.house"
SERVICE_NAME="sacha.house.service"
BINARY_NAME="sacha.house-linux-amd64"
SERVICE_USER="sacha"
SERVICE_GROUP="sacha"
EMAIL_TO="admin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== sacha.house Setup Script ==="
echo "Install directory: $INSTALL_DIR"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    echo "Reason: Installs systemd service, creates directories in /opt, sets up crontab"
    echo "Run with: sudo $0"
    exit 1
fi

echo "[1/8] Checking service user..."
if id "$SERVICE_USER" &>/dev/null; then
    echo "  User $SERVICE_USER exists ✓"
else
    echo "  ERROR: User $SERVICE_USER does not exist"
    echo "  Please create the user first or change SERVICE_USER in this script"
    exit 1
fi

echo "[2/8] Creating installation directory..."
mkdir -p "$INSTALL_DIR"
chown $SERVICE_USER:$SERVICE_USER "$INSTALL_DIR"

echo "[3/8] Downloading latest binary..."
cd "$INSTALL_DIR"
RELEASE_DATA=$(curl -s "https://gitlab.com/api/v4/projects/sachahjkl%2Fsacha.house/releases")

if [ -z "$RELEASE_DATA" ]; then
    echo "  ERROR: Failed to fetch latest release from GitLab"
    exit 1
fi

DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o '"url":"[^"]*sacha.house-linux-amd64[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "  ERROR: Failed to find download URL in release"
    exit 1
fi

echo "  Downloading from: $DOWNLOAD_URL"
curl -L -f "$DOWNLOAD_URL" -o sacha.house
chmod +x sacha.house
chown $SERVICE_USER:$SERVICE_GROUP sacha.house
echo "  Binary installed"

echo "[4/7] Installing systemd service..."
cp "$SCRIPT_DIR/sacha.house.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
echo "  Service installed and enabled"

echo "[5/7] Installing update script..."
cp "$SCRIPT_DIR/update.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/update.sh"
chown root:root "$INSTALL_DIR/update.sh"

if [ "$EMAIL_TO" != "admin" ]; then
    sed -i "s/EMAIL_TO=\"admin\"/EMAIL_TO=\"$EMAIL_TO\"/" "$INSTALL_DIR/update.sh"
fi
echo "  Update script installed"

echo "[6/7] Setting up crontab for automatic updates..."
CRON_LINE="0 0 * * * $INSTALL_DIR/update.sh >> /var/log/sacha.house-update.log 2>&1"

if crontab -l 2>/dev/null | grep -q "$INSTALL_DIR/update.sh"; then
    echo "  Crontab entry already exists"
else
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    echo "  Crontab entry added"
fi

echo "[7/7] Creating log file..."
touch /var/log/sacha.house-update.log
chmod 644 /var/log/sacha.house-update.log

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Starting service..."
systemctl start "$SERVICE_NAME"

sleep 3

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✓ Service is running"
    systemctl status "$SERVICE_NAME" --no-pager
else
    echo "✗ Service failed to start"
    echo ""
    echo "Check logs with:"
    echo "  journalctl -u $SERVICE_NAME -n 50"
    exit 1
fi

echo ""
echo "Installation complete!"
echo ""
echo "Useful commands:"
echo "  Status:  systemctl status $SERVICE_NAME"
echo "  Logs:    journalctl -u $SERVICE_NAME -f"
echo "  Update:  $INSTALL_DIR/update.sh"
echo "  Stop:    systemctl stop $SERVICE_NAME"
echo "  Start:   systemctl start $SERVICE_NAME"
echo "  Restart: systemctl restart $SERVICE_NAME"

