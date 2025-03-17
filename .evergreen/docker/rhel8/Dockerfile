FROM registry.access.redhat.com/ubi8/ubi:8.4

# Install mongodb 4.4 server to get older deps.
RUN echo -e "\
[mongodb-enterprise-4.4] \n\
name=MongoDB Enterprise Repository \n\
baseurl=https://repo.mongodb.com/yum/redhat/8/mongodb-enterprise/4.4/$(uname -m)/ \n\
enabled         = 1 \n\
gpgkey=https://pgp.mongodb.com/server-4.4.asc \n\
gpgcheck        = 1\
" > /etc/yum.repos.d/mongodb-enterprise-4.4.repo

RUN dnf update -y && \
  dnf install -y \
    git \
    ca-certificates \
    curl \
    wget \
    sudo \
    make \
    gnupg \
    python3.9 \
    mongodb-enterprise \
    lsof < /dev/null > /dev/null

# Alias python3 -> python3.9
RUN ln -f -s /usr/bin/python3.9 /usr/bin/python3

ARG USER_ID
ARG GROUP_ID

ENV DRIVERS_TOOLS=/root/drivers-tools
ENV MONGO_ORCHESTRATION_HOME=/root/drivers-tools/.evergreen/orchestration
ENV MONGODB_BINARIES=/root/drivers-tools/mongodb/bin
ENV DOCKER_RUNNING=true

COPY . /root/drivers-tools
COPY .evergreen/docker/rhel8/*.sh /root
