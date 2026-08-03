#!/usr/bin/env bash
#
# Smoke-tests that the gcpkms/azurekms remote-scripts leave a host in a state
# where ensure_uv succeeds, without needing a real GCE/Azure VM. Runs each
# script's dependency-install step in a container and then calls ensure_uv.
set -eu

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE=drivers-tools-remote-kms-provisioning-test

# Some Evergreen hosts (e.g. RHEL) only ship podman, not docker; matches the
# engine selection in .evergreen/docker/run-server.sh.
if command -v podman &> /dev/null; then
  DOCKER="sudo podman --storage-opt ignore_chown_errors=true"
else
  DOCKER=docker
fi
if [ -n "${DOCKER_COMMAND:-}" ]; then
  DOCKER=$DOCKER_COMMAND
fi

test_provisioning() {
  local name="$1" script="$2" base_image="$3"
  echo "Testing $name provisioning ($base_image) ..."
  $DOCKER build -q -t "$IMAGE-$name" --build-arg BASE_IMAGE="$base_image" \
    -f "$SCRIPT_DIR/docker/remote-kms-provisioning.Dockerfile" "$SCRIPT_DIR/docker"
  $DOCKER run --rm -v "$ROOT_DIR:/drivers-tools:ro" "$IMAGE-$name" bash -c "
    set -e
    cp -r /drivers-tools ~/drivers-tools
    cd ~/drivers-tools
    bash $script
    . .evergreen/ensure-uv.sh
    ensure_uv
    uv --version
  "
  echo "Testing $name provisioning ... done."
}

# Keep these in sync with the defaults in create-and-setup-instance.sh
# (GCPKMS_IMAGEFAMILY) and create-and-setup-vm.sh (AZUREKMS_IMAGE).
test_provisioning gcpkms .evergreen/csfle/gcpkms/remote-scripts/setup-gce-instance.sh debian:11
test_provisioning azurekms .evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh debian:11
