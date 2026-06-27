#!/bin/sh

set -e

echo "Starting Nginx..."
nginx

echo "Starting FastTerm..."
python /app/src/main.py &
FASTAPI_PID=$!


echo "Installing/Starting code-server..."

# Install curl if not already installed
if ! command -v curl >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl
fi

# Install code-server if missing (Fixed official installer URL)
if ! command -v code-server >/dev/null 2>&1; then
    curl -fsSL https://code-server.dev | sh
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
