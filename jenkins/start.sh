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
    apt-get install -y fontconfig openjdk-17-jre
fi

# Install Jenkins if not already installed
if ! command -v jenkins >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl gnupg2

    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null

    apt-get update
    apt-get install -y jenkins
fi

# Create persistent data directory
mkdir -p /data/jenkins

# Start Jenkins in background pointing to /data/jenkins for persistence
JENKINS_HOME=/data/jenkins \
java -jar /usr/share/jenkins/jenkins.war \
    --httpPort=3000 \
    --httpListenAddress=0.0.0.0 &

wait $FASTAPI_PID
