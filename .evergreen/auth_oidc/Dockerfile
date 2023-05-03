FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive
ENV HOME /home/root
ENV DRIVERS_TOOLS $HOME/drivers-evergreen-tools

ARG AWS_SECRET_ACCESS_KEY=""
ARG AWS_ACCESS_KEY_ID=""
ARG AWS_ROLE_ARN=""
ARG NO_IPV6=""

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

COPY . $DRIVERS_TOOLS

# Install drivers-evergreen-tools and binaries.
RUN cd $DRIVERS_TOOLS && \
git clean -dffx && \
export MONGODB_VERSION=latest && \
export SKIP_LEGACY_SHELL=1 && \
. $DRIVERS_TOOLS/.evergreen/download-mongodb.sh && \
get_distro && \
get_mongodb_download_url_for "$DISTRO" "$MONGODB_VERSION" && \
download_and_extract "$MONGODB_DOWNLOAD_URL" "$EXTRACT" "$MONGOSH_DOWNLOAD_URL" "$EXTRACT_MONGOSH"

# Write the orchestration file.
SHELL ["/bin/bash", "-c"]
RUN cd $DRIVERS_TOOLS/.evergreen/auth_oidc && \
. ./activate-authoidcvenv.sh && \
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} && \
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} && \
export AWS_ROLE_ARN=${AWS_ROLE_ARN} && \
export NO_IPV6=${NO_IPV6} && \
python oidc_write_orchestration.py

COPY ./.evergreen/auth_oidc/docker_entry.sh $HOME/docker_entry.sh

ENTRYPOINT ["/bin/bash", "/home/root/docker_entry.sh"]
