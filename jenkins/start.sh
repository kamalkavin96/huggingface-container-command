#!/bin/bash
VERSION="1.0.4"
LAST_UPDATED="2026-06-14"
set -e

echo "================================================"
echo " Jenkins Entrypoint v${VERSION} (${LAST_UPDATED})"
echo "================================================"

echo "Starting Nginx..."
nginx

echo "Starting FastTerm..."
python /app/src/main.py &
FASTAPI_PID=$!

echo "Installing/Starting Jenkins..."

# Install Java if not already installed
if ! command -v java >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y fontconfig openjdk-21-jre
fi

# Download Jenkins WAR if not already present
if [ ! -f /usr/share/jenkins/jenkins.war ]; then
    apt-get update -qq
    apt-get install -y curl
    mkdir -p /usr/share/jenkins
    # JENKINS_VERSION="2.504.1"
    JENKINS_VERSION="2.555.3"
    curl -fsSL -o /usr/share/jenkins/jenkins.war \
        https://get.jenkins.io/war-stable/${JENKINS_VERSION}/jenkins.war
fi

# Ensure jenkins user exists
if ! id -u jenkins >/dev/null 2>&1; then
    useradd -m -d /var/jenkins_home -s /bin/bash jenkins
fi

BUCKET_PATH=/data/jenkins_home
LOCAL_PATH=/var/jenkins_home
RSYNC_OPTS="-a --no-owner --no-group --force"
RSYNC_EXCLUDE="--exclude=workspace/ --exclude=war/ --exclude=*.log --exclude=*.tmp --exclude=.lock"

# ── Startup restore ────────────────────────────────────────────────────────────
echo "==> Checking bucket accessibility..."
if ! timeout 10 ls /data/ > /dev/null 2>&1; then
  echo "==> Bucket not accessible, starting fresh"
else
  echo "==> Restoring secrets first..."
  rsync $RSYNC_OPTS $RSYNC_EXCLUDE \
    "$BUCKET_PATH/secrets/" "$LOCAL_PATH/secrets/" \
  && echo "==> Secrets restored OK" \
  || echo "==> Secrets restore failed (may not exist yet)"

  rsync $RSYNC_OPTS "$BUCKET_PATH/identity.key.enc" "$LOCAL_PATH/" 2>/dev/null || true
  rsync $RSYNC_OPTS "$BUCKET_PATH/secret.key"       "$LOCAL_PATH/" 2>/dev/null || true

  echo "==> Restoring full Jenkins state..."
  rsync $RSYNC_OPTS $RSYNC_EXCLUDE \
    "$BUCKET_PATH/" "$LOCAL_PATH/" \
  && echo "==> Full restore done" \
  || echo "==> Restore failed (may not exist yet)"
fi

# ── Key consistency check ──────────────────────────────────────────────────────
MASTER_KEY="$LOCAL_PATH/secrets/master.key"
IDENTITY_KEY="$LOCAL_PATH/identity.key.enc"
if [ -f "$IDENTITY_KEY" ] && [ ! -f "$MASTER_KEY" ]; then
  echo "==> WARNING: key mismatch — wiping identity"
  rm -f "$IDENTITY_KEY"
fi

mkdir -p "$LOCAL_PATH"
chown -R jenkins:jenkins "$LOCAL_PATH/"

# ── Background sync loop ───────────────────────────────────────────────────────
do_sync() {
  local TIMEOUT=$1
  timeout 30 rsync $RSYNC_OPTS $RSYNC_EXCLUDE \
    "$LOCAL_PATH/secrets/" "$BUCKET_PATH/secrets/" 2>/dev/null || true
  timeout "$TIMEOUT" rsync $RSYNC_OPTS $RSYNC_EXCLUDE \
    --delete --delete-during --timeout=30 \
    "$LOCAL_PATH/" "$BUCKET_PATH/"
}

(
  FIRST_SYNC=true
  while true; do
    sleep 30
    echo "[$(date '+%H:%M:%S')] Syncing to bucket..."
    if [ "$FIRST_SYNC" = true ]; then
      echo "[$(date '+%H:%M:%S')] First sync — using extended timeout (600s)..."
      if do_sync 600; then
        echo "[$(date '+%H:%M:%S')] First sync done"
        FIRST_SYNC=false
      else
        echo "[$(date '+%H:%M:%S')] First sync failed — will retry"
      fi
    else
      if do_sync 120; then
        echo "[$(date '+%H:%M:%S')] Sync done"
      else
        echo "[$(date '+%H:%M:%S')] Sync failed — will retry"
      fi
    fi
  done
) &
SYNC_PID=$!

# ── Shutdown handler ───────────────────────────────────────────────────────────
cleanup() {
  echo "==> Final sync before shutdown..."
  timeout 30 rsync $RSYNC_OPTS $RSYNC_EXCLUDE \
    "$LOCAL_PATH/secrets/" "$BUCKET_PATH/secrets/" || true
  timeout 180 rsync $RSYNC_OPTS $RSYNC_EXCLUDE \
    --delete --delete-during \
    "$LOCAL_PATH/" "$BUCKET_PATH/" || true
  echo "==> Shutdown sync complete"
  kill $SYNC_PID 2>/dev/null || true
  kill $JENKINS_PID 2>/dev/null || true
  kill $FASTAPI_PID 2>/dev/null || true
  exit 0
}
trap cleanup SIGTERM SIGINT

# ── Start Jenkins ──────────────────────────────────────────────────────────────
echo "==> Starting Jenkins on port 3000..."
JENKINS_HOME="$LOCAL_PATH" \
su -s /bin/bash jenkins -c \
  "java -jar /usr/share/jenkins/jenkins.war --httpPort=3000 --httpListenAddress=0.0.0.0" &
JENKINS_PID=$!

# Wait for either process to exit
wait $FASTAPI_PID $JENKINS_PID
