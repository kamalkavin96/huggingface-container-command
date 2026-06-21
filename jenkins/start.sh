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

# Install Jenkins WAR if not already present
if [ ! -f /data/jenkins/jenkins.war ]; then
    apt-get update
    apt-get install -y curl

    mkdir -p /data/jenkins

    JENKINS_VERSION="2.504.1"
    curl -fsSL -o /data/jenkins/jenkins.war \
        https://get.jenkins.io/war-stable/${JENKINS_VERSION}/jenkins.war
fi

# Create persistent data directory
mkdir -p /data/jenkins

# Start Jenkins in background pointing to /data/jenkins for persistence
JENKINS_HOME=/data/jenkins \
java -jar /data/jenkins/jenkins.war \
    --httpPort=3000 \
    --httpListenAddress=0.0.0.0 &

wait $FASTAPI_PID
