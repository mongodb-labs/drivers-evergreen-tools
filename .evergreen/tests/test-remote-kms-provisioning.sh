#!/usr/bin/env bash
#
# Smoke-tests that the gcpkms/azurekms remote-scripts leave a host in a state
# where ensure_uv succeeds, without needing a real GCE/Azure VM. Runs each
# script's dependency-install step in a container and then calls ensure_uv.
set -eu

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE=drivers-tools-remote-kms-provisioning-test

docker build -q -t "$IMAGE" -f "$SCRIPT_DIR/docker/remote-kms-provisioning.Dockerfile" "$SCRIPT_DIR/docker"

test_provisioning() {
  local name="$1" script="$2"
  echo "Testing $name provisioning ..."
  docker run --rm -v "$ROOT_DIR:/drivers-tools:ro" "$IMAGE" bash -c "
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

test_provisioning gcpkms .evergreen/csfle/gcpkms/remote-scripts/setup-gce-instance.sh
test_provisioning azurekms .evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh
