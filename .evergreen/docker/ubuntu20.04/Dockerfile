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

RUN addgroup --gid $GROUP_ID user
RUN adduser --disabled-password --gecos '' --uid $USER_ID --gid $GROUP_ID user
USER user

ENV DRIVERS_TOOLS=/root/drivers-evergreen-tools
ENV PROJECT_ORCHESTRATION_HOME=/root/drivers-evergreen-tools/.evergreen/orchestration
ENV MONGODB_BINARIES=/root/drivers-evergreen-tools/mongodb/bin
ENV MONGO_ORCHESTRATION_HOME=/root
ENV SKIP_LEGACY_SHELL=1
ENV DOCKER_RUNNING=true

COPY ./local-entrypoint.sh /root/local-entrypoint.sh
COPY ./test-entrypoint.sh /root/test-entrypoint.sh
