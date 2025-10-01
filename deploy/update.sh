#!/bin/bash

set -e

INSTALL_DIR="/opt/sacha.house"
SERVICE_NAME="sacha.house.service"
BINARY_NAME="sacha.house"
GITLAB_PROJECT="sachahjkl%2Fsacha.house"
GITLAB_URL="https://gitlab.com"
EMAIL_TO="admin"

cd "$INSTALL_DIR"

echo "Stopping service..."
sudo systemctl stop "$SERVICE_NAME"

if [ -f "$BINARY_NAME" ]; then
    echo "Backing up current binary..."
    cp "$BINARY_NAME" "${BINARY_NAME}.bak"
fi

echo "Fetching latest release..."
RELEASE_DATA=$(curl -s "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT}/releases" | head -1)

if [ -z "$RELEASE_DATA" ]; then
    echo "Failed to fetch latest release"
    echo "Failed to fetch latest sacha.house release from GitLab" | mail -s "sacha.house Update Failed" "$EMAIL_TO"
    exit 1
fi

DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o '"url":"[^"]*sacha.house-linux-amd64[^"]*"' | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Failed to find download URL"
    echo "Failed to find download URL in latest sacha.house release" | mail -s "sacha.house Update Failed" "$EMAIL_TO"
    exit 1
fi

echo "Downloading binary from $DOWNLOAD_URL..."
curl -L "$DOWNLOAD_URL" -o "${BINARY_NAME}.new"

chmod +x "${BINARY_NAME}.new"
mv "${BINARY_NAME}.new" "$BINARY_NAME"

echo "Starting service..."
sudo systemctl start "$SERVICE_NAME"

sleep 5

if ! sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "Service failed to start, rolling back..."
    
    if [ -f "${BINARY_NAME}.bak" ]; then
        mv "${BINARY_NAME}.bak" "$BINARY_NAME"
        sudo systemctl start "$SERVICE_NAME"
        
        if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
            echo "Rollback successful"
            echo "Service failed to start with new binary. Rolled back to previous version." | mail -s "sacha.house Update Failed" "$EMAIL_TO"
        else
            echo "Rollback failed"
            echo "Service failed to start even after rollback. Manual intervention required." | mail -s "sacha.house CRITICAL FAILURE" "$EMAIL_TO"
        fi
    else
        echo "No backup available for rollback"
        echo "Service failed to start and no backup available for rollback." | mail -s "sacha.house Update Failed" "$EMAIL_TO"
    fi
    exit 1
fi

echo "Update successful"
echo "Successfully updated sacha.house to latest release" | mail -s "sacha.house Updated" "$EMAIL_TO"

rm -f "${BINARY_NAME}.bak"

