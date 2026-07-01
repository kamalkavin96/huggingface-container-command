#!/bin/bash
set -e

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "===== Application Startup ====="

DATA_DIR="${DATA_DIR:-/data}"
PGDATA="$DATA_DIR/postgres"
NC_DATADIR="$DATA_DIR/nextcloud-data"
NC_CONFIG="/var/www/nextcloud/config/config.php"

POSTGRES_DB="${POSTGRES_DB:-nextcloud}"
POSTGRES_USER="${POSTGRES_USER:-nextcloud}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD as a Space secret}"
NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"
: "${NEXTCLOUD_ADMIN_PASSWORD:?Set NEXTCLOUD_ADMIN_PASSWORD as a Space secret}"
SPACE_HOST="${SPACE_HOST:-localhost}"
FASTAPI_PORT="${PORT:-8000}"

# FastTerm's own persistent data (SQLite DB + uploaded files) -- also on /data
FASTTERM_SQLITE_DIR="$DATA_DIR/webterm-db"
FASTTERM_FILES_DIR="$DATA_DIR/webterm-files"

mkdir -p "$PGDATA" "$NC_DATADIR" "$FASTTERM_SQLITE_DIR" "$FASTTERM_FILES_DIR"
chown -R postgres:postgres "$PGDATA"
chown -R www-data:www-data "$NC_DATADIR"

# ---------------------------------------------------------------------------
# Postgres  (data dir persisted at $PGDATA, under /data)
# ---------------------------------------------------------------------------
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    log "Initializing Postgres cluster..."
    gosu postgres initdb -D "$PGDATA" --auth=trust >/dev/null
fi

log "Starting Postgres..."
gosu postgres pg_ctl -D "$PGDATA" -l "$DATA_DIR/postgres.log" \
    -o "-c listen_addresses='127.0.0.1'" start \
    || { log "ERROR: Failed to start Postgres"; exit 1; }

until gosu postgres pg_isready -q; do sleep 1; done
log "Postgres is ready."

gosu postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$POSTGRES_USER'" | grep -q 1 \
    || gosu postgres psql -c "CREATE ROLE $POSTGRES_USER LOGIN PASSWORD '$POSTGRES_PASSWORD';"
gosu postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$POSTGRES_DB'" | grep -q 1 \
    || gosu postgres psql -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;"

# ---------------------------------------------------------------------------
# Nextcloud (installer runs once, skipped on later boots)
# Served at the domain root via the internal :3000 nginx server -- no
# subdirectory webroot config needed. Data dir persisted under /data.
# ---------------------------------------------------------------------------
if [ ! -f "$NC_CONFIG" ]; then
    log "Running Nextcloud installer..."
    gosu www-data php /var/www/nextcloud/occ maintenance:install \
        --database "pgsql" \
        --database-name "$POSTGRES_DB" \
        --database-user "$POSTGRES_USER" \
        --database-pass "$POSTGRES_PASSWORD" \
        --database-host "127.0.0.1" \
        --admin-user "$NEXTCLOUD_ADMIN_USER" \
        --admin-pass "$NEXTCLOUD_ADMIN_PASSWORD" \
        --data-dir "$NC_DATADIR" \
        || { log "ERROR: Nextcloud install failed"; exit 1; }
else
    log "Nextcloud already installed, skipping installer."
fi

gosu www-data php /var/www/nextcloud/occ config:system:set trusted_domains 1 --value="$SPACE_HOST"
gosu www-data php /var/www/nextcloud/occ config:system:set overwritehost --value="$SPACE_HOST"
gosu www-data php /var/www/nextcloud/occ config:system:set overwriteprotocol --value="https"
gosu www-data php /var/www/nextcloud/occ config:system:set overwrite.cli.url --value="https://$SPACE_HOST/"
gosu www-data php /var/www/nextcloud/occ config:system:set trusted_proxies 0 --value="127.0.0.1"

# ---------------------------------------------------------------------------
# PHP-FPM (foreground, backgrounded by shell so we can track its PID)
# ---------------------------------------------------------------------------
PHP_FPM_BIN="$(command -v php-fpm8.2 || command -v php-fpm || ls /usr/sbin/php-fpm* | head -n1)"
log "Starting PHP-FPM ($PHP_FPM_BIN)..."
"$PHP_FPM_BIN" -F &
PHP_FPM_PID=$!
log "PHP-FPM started with PID: $PHP_FPM_PID"

# ---------------------------------------------------------------------------
# FastTerm (FastAPI) -- SQLite DB and file storage also on /data
# ---------------------------------------------------------------------------
log "Starting FastTerm..."
PORT="$FASTAPI_PORT" \
SQLITE_DB_PATH="$FASTTERM_SQLITE_DIR" \
WEBTERM_FILES_ROOT="$FASTTERM_FILES_DIR" \
python /app/src/main.py &
FASTAPI_PID=$!
log "FastTerm started with PID: $FASTAPI_PID"

# ---------------------------------------------------------------------------
# Nginx (single process, two server blocks: 7860 public, 3000 internal for
# Nextcloud)
# ---------------------------------------------------------------------------
log "Starting Nginx..."
nginx || { log "ERROR: Failed to start Nginx"; exit 1; }

# ---------------------------------------------------------------------------
# Stay alive as long as PHP-FPM and FastAPI are both up. If either dies,
# exit so the Space restarts the container.
# ---------------------------------------------------------------------------
log "Startup complete. Watching PHP-FPM (PID $PHP_FPM_PID) and FastTerm (PID $FASTAPI_PID)..."
wait -n "$PHP_FPM_PID" "$FASTAPI_PID"
log "One of the core services exited -- shutting down."
exit 1
