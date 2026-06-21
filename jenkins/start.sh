#!/bin/sh

set -e

echo "Starting Nginx..."
nginx

echo "Starting FastTerm..."
python /app/src/main.py &
FASTAPI_PID=$!

echo "Installing/Starting Jenkins..."

# Install Java if not already installed
if ! command -v java >/dev/null 2>&1; then
    apt-get update
    apt-get install -y fontconfig openjdk-21-jre
fi

# Install Jenkins if not already installed
if [ ! -f /usr/share/jenkins/jenkins.war ]; then
    apt-get update
    apt-get install -y curl

    # Download Jenkins WAR directly — avoids apt repo GPG issues entirely
    JENKINS_VERSION="2.504.1"
    curl -fsSL -o /usr/share/jenkins/jenkins.war \
        https://get.jenkins.io/war-stable/${JENKINS_VERSION}/jenkins.war
fi

# Create persistent data directory
mkdir -p /data/jenkins

# Start Jenkins in background pointing to /data/jenkins for persistence
JENKINS_HOME=/data/jenkins \
java -jar /usr/share/jenkins/jenkins.war \
    --httpPort=3000 \
    --httpListenAddress=0.0.0.0 &

wait $FASTAPI_PID
