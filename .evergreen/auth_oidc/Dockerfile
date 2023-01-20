FROM ubuntu:20.04

RUN apt-get update -qq && apt-get install -qqy --no-install-recommends \
  git \
  ca-certificates \
  curl \
  wget \
  sudo \
  gnupg \
 && rm -rf /var/lib/apt/lists/*

ARG DEBIAN_FRONTEND=noninteractive

# Set up mongodb enterprise dependencies
RUN wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
RUN echo "deb [ arch=amd64,arm64 ] http://repo.mongodb.com/apt/ubuntu focal/mongodb-enterprise/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-enterprise.list
RUN apt-get update && apt-get install -qqy --no-install-recommends \
  mongodb-enterprise \
 && rm -rf /var/lib/apt/lists/*

# create the ubuntu user
RUN addgroup --gid 1000 ubuntu \
 && adduser --gecos "" \
      --shell /bin/bash \
      --uid 1000 \
      --gid 1000 \
      --disabled-password \
      ubuntu \
 && adduser ubuntu sudo
RUN echo 'ubuntu:password' | chpasswd

# change to the ubuntu user
USER ubuntu
WORKDIR /home/ubuntu

# Copy ourselves
COPY . drivers-evergreen-tools