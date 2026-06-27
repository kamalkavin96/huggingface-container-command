#!/bin/sh

set -e

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "===== Application Startup ====="

# Start Nginx
log "Starting Nginx..."
nginx || { log "ERROR: Failed to start Nginx"; exit 1; }

# Start FastTerm
log "Starting FastTerm..."
python /app/src/main.py &
FASTAPI_PID=$!

# Install code-server
log "Installing/Starting code-server..."

# Ensure curl is installed
if ! command -v curl >/dev/null 2>&1; then
    log "Installing curl..."
    apt-get update -qq
    apt-get install -y -qq curl
fi

# Install code-server using official install script if not already installed
if ! command -v code-server >/dev/null 2>&1; then
    log "Installing code-server using official install script..."
    
    # Download and execute the official install script
    # Using --dry-run first to check, then actual install
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/usr/local
    
    # Verify installation
    if ! command -v code-server >/dev/null 2>&1; then
        log "ERROR: code-server installation failed!"
        exit 1
    fi
    
    log "code-server installed successfully: $(code-server --version)"
else
    log "code-server already installed: $(code-server --version)"
fi

# Create persistent storage directories inside /data
log "Creating workspace directories..."
mkdir -p /data/code-server-home
mkdir -p /data/workspace

# Set proper permissions
chmod -R 755 /data/code-server-home
chmod -R 755 /data/workspace

# Start code-server in background
log "Starting code-server on port 9001..."
HOME=/data/code-server-home \
PROXY_DOMAIN_PATH="/vs-code" \
code-server \
  --bind-addr 0.0.0.0:9001 \
  --auth none \
  --disable-telemetry \
  /data/workspace &

CODE_SERVER_PID=$!
log "code-server started with PID: $CODE_SERVER_PID"

# Wait for FastAPI process
log "Waiting for FastTerm service..."
wait $FASTAPI_PID
