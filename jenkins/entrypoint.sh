#!/bin/bash
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
  || echo "==> Secrets restore failed"

  rsync $RSYNC_OPTS "$BUCKET_PATH/identity.key.enc" "$LOCAL_PATH/" 2>/dev/null
  rsync $RSYNC_OPTS "$BUCKET_PATH/secret.key"       "$LOCAL_PATH/" 2>/dev/null

  echo "==> Restoring full Jenkins state (no timeout — waiting for completion)..."
  rsync $RSYNC_OPTS $RSYNC_EXCLUDE \
    "$BUCKET_PATH/" "$LOCAL_PATH/" \
  && echo "==> Full restore done" \
  || echo "==> Restore failed"
fi

# ── Key consistency check ──────────────────────────────────────────────────────
MASTER_KEY="$LOCAL_PATH/secrets/master.key"
IDENTITY_KEY="$LOCAL_PATH/identity.key.enc"
if [ -f "$IDENTITY_KEY" ] && [ ! -f "$MASTER_KEY" ]; then
  echo "==> WARNING: key mismatch — wiping identity"
  rm -f "$IDENTITY_KEY"
fi

chown -R jenkins:jenkins "$LOCAL_PATH/"

# ── Background sync loop ───────────────────────────────────────────────────────
do_sync() {
  local TIMEOUT=$1

  # Secrets first
  timeout 30 rsync $RSYNC_OPTS $RSYNC_EXCLUDE \
    "$LOCAL_PATH/secrets/" "$BUCKET_PATH/secrets/" 2>/dev/null

  # Full sync
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
    "$LOCAL_PATH/secrets/" "$BUCKET_PATH/secrets/"
  timeout 180 rsync $RSYNC_OPTS $RSYNC_EXCLUDE \
    --delete --delete-during \
    "$LOCAL_PATH/" "$BUCKET_PATH/"
  echo "==> Shutdown sync complete"
  kill $SYNC_PID 2>/dev/null
  exit 0
}
trap cleanup SIGTERM SIGINT

exec java -jar /usr/share/jenkins/jenkins.war --httpPort=7860