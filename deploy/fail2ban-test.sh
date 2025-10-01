#!/bin/bash

ORIGINAL_LOG_DIR="/data/Docker/appdata/Nginx Proxy Manager/data/logs"
SYMLINK_DIR="/var/log/nginx-proxy-manager"

echo "=== fail2ban Log Path Tester ==="
echo ""

echo "1. Checking original directory..."
if [ -d "$ORIGINAL_LOG_DIR" ]; then
    echo "✓ Original directory exists: $ORIGINAL_LOG_DIR"
else
    echo "✗ Directory not found: $ORIGINAL_LOG_DIR"
    exit 1
fi

echo ""
echo "2. Checking/creating symlink..."
if [ -L "$SYMLINK_DIR" ]; then
    echo "✓ Symlink exists: $SYMLINK_DIR -> $(readlink $SYMLINK_DIR)"
elif [ ! -e "$SYMLINK_DIR" ]; then
    echo "Creating symlink..."
    sudo ln -s "$ORIGINAL_LOG_DIR" "$SYMLINK_DIR"
    echo "✓ Symlink created"
else
    echo "✗ $SYMLINK_DIR exists but is not a symlink"
    exit 1
fi

echo ""
echo "3. Listing access log files via symlink..."
ls -lh "$SYMLINK_DIR"/proxy-host-*_access.log 2>/dev/null || {
    echo "✗ No proxy-host-*_access.log files found"
    echo "Files in directory:"
    ls -lh "$SYMLINK_DIR" | head -20
    exit 1
}

echo ""
echo "4. Testing filter against sample log lines..."
SAMPLE_LOG=$(ls "$SYMLINK_DIR"/proxy-host-*_access.log 2>/dev/null | head -1)

if [ -n "$SAMPLE_LOG" ]; then
    echo "Using: $SAMPLE_LOG"
    echo ""
    echo "Lines containing '/teapot':"
    grep "/teapot" "$SAMPLE_LOG" | head -5
    
    echo ""
    echo "Testing fail2ban filter..."
    fail2ban-regex "$SAMPLE_LOG" /etc/fail2ban/filter.d/sacha-house-teapot.conf || {
        echo ""
        echo "Filter test failed. Sample log line format:"
        head -2 "$SAMPLE_LOG"
    }
else
    echo "✗ No log file to test"
fi

