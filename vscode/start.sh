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
    
    # Query GitHub API safely to extract the actual structural tag string
    VERSION=$(curl -s https://github.com | jq -r '.tag_name' | sed 's/^v//')
    
    echo "Downloading stable Ubuntu package version: v${VERSION}..."
    # Downloads the compiled native Debian package file directly 
    curl -fOL "https://github.com/coder/code-server/releases/download/v${VERSION}/code-server_${VERSION}_amd64.deb"
    
    echo "Installing package natively..."
    dpkg -i "code-server_${VERSION}_amd64.deb"
    
    # Clean up installation package
    rm "code-server_${VERSION}_amd64.deb"
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
