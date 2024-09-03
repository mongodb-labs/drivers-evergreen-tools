FROM ubuntu:20.04

RUN export DEBIAN_FRONTEND=noninteractive && \
  apt-get -qq update && apt-get -qq -y install --no-install-recommends \
  git \
  ca-certificates \
  curl \
  wget \
  make \
  sudo \
  gnupg \
  python \
  python3 \
  python3.8-venv \
  lsof \
  software-properties-common \
  libsnmp35 \
  net-tools < /dev/null > /dev/null \
 && rm -rf /var/lib/apt/lists/*

ARG USER_ID
ARG GROUP_ID

ENV DRIVERS_TOOLS=/root/drivers-evergreen-tools
ENV PROJECT_ORCHESTRATION_HOME=/root/drivers-evergreen-tools/.evergreen/orchestration
ENV MONGODB_BINARIES=/root/drivers-evergreen-tools/.evergreen/docker/ubuntu20.04/mongodb/bin
ENV MONGO_ORCHESTRATION_HOME=/root/drivers-evergreen-tools/.evergreen/docker/ubuntu20.04/orchestration
ENV DOCKER_RUNNING=true

COPY ./local-entrypoint.sh /root/local-entrypoint.sh
COPY ./base-entrypoint.sh /root/base-entrypoint.sh
COPY ./test-entrypoint.sh /root/test-entrypoint.sh
