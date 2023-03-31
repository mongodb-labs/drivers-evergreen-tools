FROM ubuntu:20.04

RUN apt-get -qq update && apt-get -qqy -o DPkg::Lock::Timeout=-1 install --no-install-recommends \
  git \
  ca-certificates \
  curl \
  wget \
  sudo \
  gnupg \
  python \
  python3 \
  python3-virtualenv \
  lsof \
  libsnmp35 \
  net-tools \
 && rm -rf /var/lib/apt/lists/*

COPY ./docker_entry.sh /home/root/docker_entry.sh

ENTRYPOINT ["/bin/bash", "/home/root/docker_entry.sh"]
