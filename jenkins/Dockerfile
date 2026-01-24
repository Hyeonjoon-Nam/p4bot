# jenkins/Dockerfile

# 1. Use the official Jenkins LTS (Long Term Support) image as the base
FROM jenkins/jenkins:lts

# 2. Switch to root user to install system packages
USER root

# 3. Install Docker CLI
# This enables the Jenkins container to execute docker commands (e.g., 'docker build', 'docker exec')
# by communicating with the host's Docker daemon.
RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli

# 4. Switch back to the jenkins user for security (best practice)
USER jenkins