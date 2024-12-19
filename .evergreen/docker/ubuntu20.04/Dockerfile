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

ENV DRIVERS_TOOLS=/root/drivers-tools
ENV ENTRYPOINTS=/root/drivers-tools/.evergreen/docker/ubuntu20.04
ENV MONGO_ORCHESTRATION_HOME=/root/drivers-tools/.evergreen/orchestration
ENV DOCKER_RUNNING=true

COPY . /root/drivers-tools
