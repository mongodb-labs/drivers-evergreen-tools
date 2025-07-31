ARG IMAGE_NAME=ubuntu:20.04
FROM $IMAGE_NAME

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
  lsof \
  software-properties-common \
  libsnmp35 \
  net-tools < /dev/null > /dev/null \
 && rm -rf /var/lib/apt/lists/*

# Install python 3.10 from ppa
RUN export DEBIAN_FRONTEND=noninteractive \
&& export TZ=Etc/UTC \
&& add-apt-repository ppa:deadsnakes/ppa \
&& apt-get -qq update \
&& apt-get -qq -y install python3.10 python3.10-venv < /dev/null > /dev/null \
&& ln -sf /usr/bin/python3.10 /usr/bin/python3 \
&& rm -rf /var/lib/apt/lists/*

ARG USER_ID
ARG GROUP_ID

ENV DRIVERS_TOOLS=/root/drivers-tools
ENV MONGO_ORCHESTRATION_HOME=/root/drivers-tools/.evergreen/orchestration
ENV MONGODB_BINARIES=/root/drivers-tools/mongodb/bin
ENV DOCKER_RUNNING=true

COPY . /root/drivers-tools
COPY .evergreen/docker/ubuntu20.04/*.sh /root
