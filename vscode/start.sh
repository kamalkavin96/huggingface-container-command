#!/bin/sh

set -e

echo "Starting Nginx..."
nginx

echo "Starting FastTerm..."
python /app/src/main.py &
FASTAPI_PID=$!


echo "Installing/Starting code-server..."

# Ensure curl and jq are installed
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl jq
fi

# Install code-server via native Debian package if missing
if ! command -v code-server >/dev/null 2>&1; then
    echo "Fetching latest stable code-server package metadata..."
    
    # Query GitHub Releases API correctly to get the latest tag
    VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | jq -r '.tag_name' | sed 's/^v//')
    
    if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
        echo "ERROR: Failed to fetch code-server version. Using fallback version..."
        VERSION="4.92.2"  # Known stable version as fallback
    fi
    
    echo "Downloading stable Ubuntu package version: v${VERSION}..."
    DEB_FILE="code-server_${VERSION}_amd64.deb"
    
    # Download the actual .deb package
    curl -fL -o "$DEB_FILE" "https://github.com/coder/code-server/releases/download/v${VERSION}/${DEB_FILE}"
    
    # Verify it's actually a deb file
    if file "$DEB_FILE" | grep -q "Debian binary package"; then
        echo "Installing package natively..."
        dpkg -i "$DEB_FILE"
        
        # Clean up installation package
        rm "$DEB_FILE"
    else
        echo "ERROR: Downloaded file is not a valid .deb package"
        file "$DEB_FILE"
        exit 1
    fi
fi

# Create persistent storage directories inside /data
mkdir -p /data/code-server-home
mkdir -p /data/workspace

# Start code-server in background
HOME=/data/code-server-home \
PROXY_DOMAIN_PATH="/vs-code" \
code-server \
  --bind-addr 0.0.0.0:9001 \
  --auth none \
  /data/workspace &

wait $FASTAPI_PID
