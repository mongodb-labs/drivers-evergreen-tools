FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive

# Set up mongodb-enterprise repo.
RUN apt-get -qq update && apt-get -qqy install gnupg curl sudo && \
curl -fsSL https://pgp.mongodb.com/server-6.0.asc | \
 sudo gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg \
 --dearmor && \
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.com/apt/ubuntu jammy/mongodb-enterprise/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-enterprise-6.0.list

# Install deps.
RUN apt-get -qq update && apt-get -qqy install --no-install-recommends \
  git \
  wget \
  python3 \
  python3-virtualenv \
  lsof \
  mongodb-enterprise \
&& rm -rf /var/lib/apt/lists/*

ARG AWS_SECRET_ACCESS_KEY=""
ARG AWS_ACCESS_KEY_ID=""
ARG AWS_ROLE_ARN=""

# Install drivers-evergreen-tools and binaries, and write orchestration file.
SHELL ["/bin/bash", "-c"]
RUN export DRIVERS_TOOLS=/home/root/drivers-evergreen-tools && \
git clone --branch DRIVERS-2415-8 https://github.com/blink1073/drivers-evergreen-tools.git $DRIVERS_TOOLS && \
# Download mongodb and mongosh.
export MONGODB_VERSION=latest && \
cd $DRIVERS_TOOLS/.evergreen && \
. ./download-mongodb.sh && \
get_distro && \
get_mongodb_download_url_for "$DISTRO" "$MONGODB_VERSION" && \
download_and_extract "$MONGODB_DOWNLOAD_URL" "$EXTRACT" "$MONGOSH_DOWNLOAD_URL" "$EXTRACT_MONGOSH" && \
# Write orchestration file.
cd ./auth_oidc && \
. ./activate-authoidcvenv.sh && \
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} && \
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} && \
export AWS_ROLE_ARN=${AWS_ROLE_ARN} && \
python oidc_write_orchestration.py

COPY ./docker_entry.sh /home/root/docker_entry.sh

ENTRYPOINT ["/bin/bash", "/home/root/docker_entry.sh"]
