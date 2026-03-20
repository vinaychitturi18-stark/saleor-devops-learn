FROM jenkins/inbound-agent:latest

USER root

# Install Docker CLI and AWS CLI dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

USER jenkins
