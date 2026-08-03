# Mirrors the environment the gcpkms/azurekms remote-scripts actually run in:
# a fresh Debian 11 host, reached as a non-root user with passwordless sudo.
FROM debian:11
# man-db ships preinstalled on the real GCE/Azure base images; the
# remote-scripts assume it's there when they silence its update trigger.
RUN apt-get update && apt-get install -y sudo man-db && \
    useradd -m -s /bin/bash remote && \
    echo "remote ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/remote
USER remote
WORKDIR /home/remote
