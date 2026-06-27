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

# Install code-server using dynamic stable asset if missing
if ! command -v code-server >/dev/null 2>&1; then
    echo "Fetching latest stable code-server download URL..."
    # Dynamically gets the latest release tag name and constructs the standard asset URL
    VERSION=$(curl -s https://github.com | jq -r '.tag_name' | sed 's/^v//')
    DOWNLOAD_URL="https://github.com/coder/code-server/releases/download/v${VERSION}/code-server-${VERSION}-linux-amd64.tar.gz"
    
    echo "Downloading stable archive version: v${VERSION}..."
    curl -fL -o /tmp/code-server.tar.gz "$DOWNLOAD_URL"
    
    echo "Extracting binary components..."
    tar -xzf /tmp/code-server.tar.gz -C /tmp/
    
    echo "Moving binary to local paths..."
    mv /tmp/code-server-${VERSION}-linux-amd64/bin/code-server /usr/local/bin/code-server
    mv /tmp/code-server-${VERSION}-linux-amd64/lib /usr/local/lib/code-server
    
    # Clean up temp assets
    rm -rf /tmp/code-server*
fi

# Create persistent storage directories inside /data
mkdir -p /data/code-server-home
mkdir -p /data/workspace

# Start code-server in background
HOME=/data/code-server-home \
PROXY_DOMAIN_PATH="/vs-code" \
PATH="/usr/local/lib/code-server:$PATH" \
code-server \
  --bind-addr 0.0.0.0:9001 \
  --auth none \
  /data/workspace &

wait $FASTAPI_PID
