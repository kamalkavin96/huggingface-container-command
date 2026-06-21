#!/bin/sh

set -e

echo "Starting Nginx..."
nginx

echo "Starting FastTerm..."
python /app/src/main.py &
FASTAPI_PID=$!

echo "Installing/Starting n8n..."

# Install Node.js if not already installed
if ! command -v node >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
fi

# Install n8n globally if not already installed
if ! command -v n8n >/dev/null 2>&1; then
    npm install -g n8n
fi

# Create persistent data directory
mkdir -p /data

# Start n8n in background
N8N_USER_FOLDER=/data \
N8N_PORT=3000 \
N8N_PROTOCOL=http \
N8N_HOST=0.0.0.0 \
EXECUTIONS_DATA_PRUNE=true \
EXECUTIONS_DATA_MAX_AGE=168 \
n8n start &

wait $FASTAPI_PID
