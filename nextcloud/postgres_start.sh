#!/bin/bash
set -e

DATA_DIR="/data/postgres_storage"
DEFAULT_DIR="/var/lib/postgresql/17/main"
MARKER="$DATA_DIR/PG_VERSION"

DB_USER="${POSTGRES_USER:-nextclouduser}"
DB_PASS="${POSTGRES_PASSWORD:-nextcloudpass}"
DB_NAME="${POSTGRES_DB:-nextcloud}"

# --- Install dependencies (safe to run every boot, apt skips if present) ---
apt update
apt install -y postgresql-17 postgresql-contrib-17 sudo nano rsync

# --- Ensure target directory exists with correct perms ---
sudo mkdir -p "$DATA_DIR"
sudo chown -R postgres:postgres "$DATA_DIR"
sudo chmod 700 "$DATA_DIR"

if [ -f "$MARKER" ]; then
  # --- Persistent data already exists: reuse it, do NOT touch it ---
  echo "Existing Postgres data found in $DATA_DIR — reusing, skipping migration."
else
  # --- First boot: migrate default cluster data into persistent volume ---
  echo "No existing data in $DATA_DIR — running first-time migration."

  sudo pg_ctlcluster 17 main stop || true

  sudo rsync -av "$DEFAULT_DIR/" "$DATA_DIR/"
  sudo chown -R postgres:postgres "$DATA_DIR"
  sudo chmod 700 "$DATA_DIR"

  if [ -d "$DEFAULT_DIR" ]; then
    sudo mv "$DEFAULT_DIR" "${DEFAULT_DIR}.bak"
  fi
fi

# --- Point Postgres config at the persistent directory (idempotent) ---
sudo sed -i "s|data_directory = .*|data_directory = '$DATA_DIR'|g" /etc/postgresql/17/main/postgresql.conf

# --- Start Postgres ---
sudo pg_ctlcluster 17 main start || {
  echo "Start failed, dumping log:"
  cat /var/log/postgresql/postgresql-17-main.log
  exit 1
}

# --- Verify ---
sudo -u postgres psql -c "SHOW data_directory;"

# --- Create app user/db ONLY if they don't already exist (idempotent) ---
USER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'")
if [ "$USER_EXISTS" != "1" ]; then
  echo "Creating role ${DB_USER}..."
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
else
  echo "Role ${DB_USER} already exists — skipping creation."
  # Optional: keep password in sync with env var on every boot
  sudo -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
fi

DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'")
if [ "$DB_EXISTS" != "1" ]; then
  echo "Creating database ${DB_NAME}..."
  sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
else
  echo "Database ${DB_NAME} already exists — skipping creation."
fi

echo "Postgres ready, using persistent data at $DATA_DIR"
