#!/bin/bash
set -e

mkdir -p /data/db
chmod -R 777 /data 2>/dev/null || true

echo "Starting MongoDB..."
mongod --dbpath /data/db \
       --bind_ip 127.0.0.1 \
       --port 27017 \
       --fork \
       --logpath /data/mongod.log

until mongosh --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo "Waiting for MongoDB..."
  sleep 1
done
echo "MongoDB is up."

echo "Starting RestHeart..."
exec java -jar restheart.jar