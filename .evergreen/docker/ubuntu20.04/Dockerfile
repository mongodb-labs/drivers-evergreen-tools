FROM ubuntu:20.04

RUN export DEBIAN_FRONTEND=noninteractive && \
  apt-get -qq update && apt-get -qqy install --no-install-recommends \
  git \
  ca-certificates \
  curl \
  wget \
  sudo \
  gnupg \
  python \
  python3 \
  python3.8-venv \
  lsof \
  software-properties-common \
  libsnmp35 \
  net-tools \
 && rm -rf /var/lib/apt/lists/*

ARG USER_ID
ARG GROUP_ID

COPY ./local-entrypoint.sh /root/local-entrypoint.sh
COPY ./base-entrypoint.sh /root/base-entrypoint.sh
COPY ./test-entrypoint.sh /root/test-entrypoint.sh
