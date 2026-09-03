# Mirrors the environment the gcpkms/azurekms remote-scripts actually run in:
# a fresh host reached as a non-root user with passwordless sudo. BASE_IMAGE
# lets gcpkms and azurekms test against their own default VM image versions.
ARG BASE_IMAGE=debian:12
FROM ${BASE_IMAGE}
# man-db ships preinstalled on the real GCE/Azure base images; the
# remote-scripts assume it's there when they silence its update trigger.
RUN apt-get update && apt-get install -y sudo man-db && \
    useradd -m -s /bin/bash remote && \
    echo "remote ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/remote
USER remote
WORKDIR /home/remote
