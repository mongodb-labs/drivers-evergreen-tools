FROM ubuntu:18.04

RUN export DEBIAN_FRONTEND=noninteractive && \
  apt-get -qq update && apt-get -qq install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    wget \
    sudo \
    gnupg \
    python \
    lsof \
    software-properties-common \
    # python3 deps
    build-essential \
    zlib1g-dev \
    libncurses5-dev \
    libgdbm-dev \
    libnss3-dev \
    libssl-dev \
    libsqlite3-dev \
    libreadline-dev \
    libffi-dev wget \
    libbz2-dev \
  && rm -rf /var/lib/apt/lists/*

# Install mongodb server to get deps
RUN export DEBIAN_FRONTEND=noninteractive \
  && export TZ=Etc/UTC \
  && curl -fsSL https://pgp.mongodb.com/server-4.4.asc | gpg -o /usr/share/keyrings/mongodb-server-4.4.gpg --dearmor \
  && echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg ] https://repo.mongodb.com/apt/ubuntu bionic/mongodb-enterprise/4.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-enterprise-4.4.list \
  && apt-get -qq update \
  && apt-get -qq install -y mongodb-enterprise \
  && rm -rf /var/lib/apt/lists/*

# Install python 3.8 from ppa
RUN export DEBIAN_FRONTEND=noninteractive \
  && export TZ=Etc/UTC \
  && add-apt-repository ppa:deadsnakes/ppa \
  && apt-get -qq update \
  && apt-get -qq install -y python3.8 python3.8-venv python3-venv \
  && ln -sf /usr/bin/python3.8 /usr/bin/python3 \
  && rm -rf /var/lib/apt/lists/*

ARG USER_ID
ARG GROUP_ID

ENV DRIVERS_TOOLS=/root/drivers-evergreen-tools
ENV PROJECT_ORCHESTRATION_HOME=/root/drivers-evergreen-tools/.evergreen/orchestration
ENV MONGODB_BINARIES=/root/drivers-evergreen-tools/.evergreen/docker/ubuntu18.04/mongodb/bin
ENV MONGODB_BINARY_ROOT=/root/drivers-evergreen-tools/.evergreen/docker/ubuntu18.04/
ENV MONGO_ORCHESTRATION_HOME=/root/drivers-evergreen-tools/.evergreen/docker/ubuntu18.04/orchestration
ENV DOCKER_RUNNING=true

COPY ./local-entrypoint.sh /root/local-entrypoint.sh
COPY ./base-entrypoint.sh /root/base-entrypoint.sh
COPY ./test-entrypoint.sh /root/test-entrypoint.sh
