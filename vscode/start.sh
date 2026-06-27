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

# Install code-server using static archive fallback if missing
if ! command -v code-server >/dev/null 2>&1; then
    echo "Downloading stable code-server archive..."
    # Downloads stable static linux-amd64 binary asset version directly 
    curl -fL -o /tmp/code-server.tar.gz https://github.com
    
    echo "Extracting binary components..."
    tar -xzf /tmp/code-server.tar.gz -C /tmp/
    
    echo "Moving binary to local paths..."
    mv /tmp/code-server-4.91.1-linux-amd64/bin/code-server /usr/local/bin/code-server
    mv /tmp/code-server-4.91.1-linux-amd64/lib /usr/local/lib/code-server
    
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
