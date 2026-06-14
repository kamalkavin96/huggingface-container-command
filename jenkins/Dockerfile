FROM jenkins/jenkins:lts-jdk17

USER root
RUN apt-get update && apt-get install -y docker.io rsync curl

# Jenkins runs on fast local disk
ENV JENKINS_HOME=/var/jenkins_home

# Add current timestamp to bust Docker cache on every build
ADD https://raw.githubusercontent.com/kamalkavin96/huggingface-container-command/refs/heads/main/jenkins/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown jenkins:jenkins /entrypoint.sh

RUN mkdir -p /var/jenkins_home && chown -R jenkins:jenkins /var/jenkins_home

EXPOSE 7860

USER jenkins
ENTRYPOINT ["/entrypoint.sh"]