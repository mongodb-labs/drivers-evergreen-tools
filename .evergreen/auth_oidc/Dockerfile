FROM drivers-evergreen-tools

COPY ./.evergreen/auth_oidc/docker_entry.sh /root/docker_entry.sh
COPY ./.evergreen/auth_oidc/docker_entry_base.sh /root/docker_entry_base.sh

ENV TOPOLOGY=replica_set
ENV DRIVERS_TOOLS=/root/drivers-tools
ENV MONGO_ORCHESTRATION_HOME=/root/drivers-tools/.evergreen/orchestration
ENV MONGODB_BINARIES=/root/drivers-tools/mongodb/bin
ENV DOCKER_RUNNING=true
