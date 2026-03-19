FROM jenkins/inbound-agent:latest

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y sudo libltdl-dev \
    && rm -rf /var/lib/apt/lists/*

USER jenkins
