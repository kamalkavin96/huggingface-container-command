#!/bin/bash
set -e

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "===== Application Startup ====="

NEXTCLOUD_VERSION="${NEXTCLOUD_VERSION:-29.0.4}"

DATA_DIR="${DATA_DIR:-/data}"
PGDATA="$DATA_DIR/postgres"
NC_APP_DIR="$DATA_DIR/nextcloud-app"     # Nextcloud code + config.php, persisted
NC_DATADIR="$DATA_DIR/nextcloud-data"    # Nextcloud user files, persisted
NC_CONFIG="$NC_APP_DIR/config/config.php"

POSTGRES_DB="${POSTGRES_DB:-nextcloud}"
POSTGRES_USER="${POSTGRES_USER:-nextcloud}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD as a Space secret}"
NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"
: "${NEXTCLOUD_ADMIN_PASSWORD:?Set NEXTCLOUD_ADMIN_PASSWORD as a Space secret}"
SPACE_HOST="${SPACE_HOST:-localhost}"
FASTAPI_PORT="${PORT:-8000}"

FASTTERM_SQLITE_DIR="$DATA_DIR/webterm-db"
FASTTERM_FILES_DIR="$DATA_DIR/webterm-files"

mkdir -p "$PGDATA" "$NC_APP_DIR" "$NC_DATADIR" "$FASTTERM_SQLITE_DIR" "$FASTTERM_FILES_DIR"

# ---------------------------------------------------------------------------
# Install Postgres + PHP-FPM + Nextcloud's PHP extensions
# (not baked into the image -- installed here every boot)
# ---------------------------------------------------------------------------
log "Installing Postgres, PHP-FPM, and dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    postgresql \
    php-fpm php-cli php-pgsql php-gd php-curl php-mbstring \
    php-xml php-zip php-intl php-bcmath php-gmp \
    unzip gosu >/dev/null

# Postgres binaries (initdb, pg_ctl, pg_isready, postgres) live under
# /usr/lib/postgresql/<version>/bin, not on the default PATH.
PG_BINDIR="$(find /usr/lib/postgresql -maxdepth 2 -type d -name bin 2>/dev/null | sort -V | tail -n1)"
if [ -z "$PG_BINDIR" ]; then
    log "ERROR: could not locate postgres bin directory after install"
    exit 1
fi
export PATH="$PG_BINDIR:$PATH"
log "Using postgres binaries from $PG_BINDIR"

# postgresql-common's postinst creates the 'postgres' user via adduser but
# swallows failures -- make sure it exists regardless.
if ! id -u postgres >/dev/null 2>&1; then
    log "postgres system user missing -- creating it"
    groupadd -r postgres 2>/dev/null || true
    useradd -r -g postgres -d /var/lib/postgresql -s /bin/bash postgres 2>/dev/null || true
    mkdir -p /var/lib/postgresql
fi
chown -R postgres:postgres "$PGDATA" /var/lib/postgresql
chown -R www-data:www-data "$NC_DATADIR" "$NC_APP_DIR"

# php-fpm: listen on TCP so nginx (separate process) can reach it
sed -i "s/^listen = .*/listen = 127.0.0.1:9000/" /etc/php/*/fpm/pool.d/www.conf
sed -i "s/^;\?listen.owner.*/listen.owner = www-data/" /etc/php/*/fpm/pool.d/www.conf
sed -i "s/^;\?listen.group.*/listen.group = www-data/" /etc/php/*/fpm/pool.d/www.conf

# ---------------------------------------------------------------------------
# Nextcloud application code -- download once, persist on /data, symlink in.
# ---------------------------------------------------------------------------
if [ ! -f "$NC_APP_DIR/occ" ]; then
    log "Downloading Nextcloud ${NEXTCLOUD_VERSION} (first run)..."
    curl -fsSL "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.zip" -o /tmp/nc.zip
    rm -rf "$NC_APP_DIR"
    unzip -q /tmp/nc.zip -d "$DATA_DIR"
    mv "$DATA_DIR/nextcloud" "$NC_APP_DIR"
    rm /tmp/nc.zip
    chown -R www-data:www-data "$NC_APP_DIR"
else
    log "Nextcloud app already present on /data, skipping download."
fi

rm -rf /var/www/nextcloud
mkdir -p /var/www
ln -s "$NC_APP_DIR" /var/www/nextcloud

# ---------------------------------------------------------------------------
# Postgres
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
# Nextcloud install (runs once -- config.php now persists on /data, so this
# is correctly skipped on every boot after the first)
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
# FastTerm (FastAPI) -- SQLite DB and file storage on /data
# ---------------------------------------------------------------------------
log "Starting FastTerm..."
PORT="$FASTAPI_PORT" \
SQLITE_DB_PATH="$FASTTERM_SQLITE_DIR" \
WEBTERM_FILES_ROOT="$FASTTERM_FILES_DIR" \
python /app/src/main.py &
FASTAPI_PID=$!
log "FastTerm started with PID: $FASTAPI_PID"

# ---------------------------------------------------------------------------
# Nginx -- config was already copied to /etc/nginx/nginx.conf by the
# Dockerfile from the repo (nginx/nginx.conf), no changes needed here.
# ---------------------------------------------------------------------------
log "Starting Nginx..."
nginx || { log "ERROR: Failed to start Nginx"; exit 1; }

# ---------------------------------------------------------------------------
# Stay alive as long as PHP-FPM and FastAPI are both up.
# ---------------------------------------------------------------------------
log "Startup complete. Watching PHP-FPM (PID $PHP_FPM_PID) and FastTerm (PID $FASTAPI_PID)..."
wait -n "$PHP_FPM_PID" "$FASTAPI_PID"
log "One of the core services exited -- shutting down."
exit 1
