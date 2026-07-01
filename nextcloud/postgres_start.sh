#!/bin/bash
set -e

DATA_DIR="/data/postgres_storage"
DEFAULT_DIR="/var/lib/postgresql/17/main"
MARKER="$DATA_DIR/PG_VERSION"

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

  # Keep the original default dir as a local backup only on first migration
  if [ -d "$DEFAULT_DIR" ]; then
    sudo mv "$DEFAULT_DIR" "${DEFAULT_DIR}.bak"
  fi
fi

# --- Point Postgres config at the persistent directory (idempotent, safe to repeat) ---
sudo sed -i "s|data_directory = .*|data_directory = '$DATA_DIR'|g" /etc/postgresql/17/main/postgresql.conf

# --- Start Postgres ---
sudo pg_ctlcluster 17 main start || {
  echo "Start failed, dumping log:"
  cat /var/log/postgresql/postgresql-17-main.log
  exit 1
}

# --- Verify ---
sudo -u postgres psql -c "SHOW data_directory;"
sudo -u postgres psql -c "\l"
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"

echo "Postgres ready, using persistent data at $DATA_DIR"
