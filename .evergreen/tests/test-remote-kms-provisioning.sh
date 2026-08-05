#!/usr/bin/env bash
#
# Smoke-tests that the gcpkms/azurekms remote-scripts leave a host in a state
# where ensure_uv succeeds, without needing a real GCE/Azure VM. Runs each
# script's dependency-install step in a container and then calls ensure_uv.
#
# Also covers the reverse direction, where the provisioning predates the current
# ensure_uv. Drivers pin $DRIVERS_TOOLS, so a VM provisioned by an older pin has
# to keep working with current code. test_provisioning alone runs both halves from
# the working tree, so it cannot catch that skew.
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

# Asserts ensure_uv works on a host provisioned by a $DRIVERS_TOOLS revision from
# before python3-pip was added to the remote-scripts. Those revisions installed
# python3-venv only, and Debian and Ubuntu disable `ensurepip` for the system
# python, so there is no way to reach pip from the system interpreter: ensure_uv
# has to get there through a venv. Drivers bump their pin on their own schedule,
# so this has to keep working indefinitely, not just until they all have.
test_no_system_pip() {
  local name="$1" base_image="$2"
  echo "Testing ensure_uv without system pip ($base_image) ..."
  $DOCKER build -q -t "$IMAGE-$name" --build-arg BASE_IMAGE="$base_image" \
    -f "$SCRIPT_DIR/docker/remote-kms-provisioning.Dockerfile" "$SCRIPT_DIR/docker"
  $DOCKER run --rm -v "$ROOT_DIR:/drivers-tools:ro" "$IMAGE-$name" bash -c '
    set -e
    # The dependency list the remote-scripts installed before python3-pip, i.e.
    # what a VM provisioned from an older pin still looks like.
    sudo apt-get -qq update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq \
      -o DPkg::Lock::Timeout=-1 install python3 python3-venv git < /dev/null > /dev/null
    if python3 -m pip --version > /dev/null 2>&1; then
      echo "expected no system pip; this test is no longer testing anything" >&2
      exit 1
    fi
    cp -r /drivers-tools ~/drivers-tools
    cd ~/drivers-tools
    . .evergreen/ensure-uv.sh
    ensure_uv
    uv --version
    # The venv is the only way through here, so confirm that is what happened
    # rather than some pip path quietly reappearing.
    case "$(command -v uv)" in
    *drivers-tools-uv-venv*) ;;
    *) echo "expected uv from the fallback venv, got $(command -v uv)" >&2; exit 1 ;;
    esac
  '
  echo "Testing ensure_uv without system pip ($base_image) ... done."
}

# The mirror image of test_no_system_pip, and the reason ensure_uv keeps both
# install paths. Evergreen's debian11 images have python3-pip but no
# python3-venv, so `python3 -m venv` fails outright and pip is the only way
# through. A venv-only ensure_uv passed every test above and still broke those
# hosts, so assert this shape too.
test_no_venv_module() {
  local name="$1" base_image="$2"
  echo "Testing ensure_uv without the venv module ($base_image) ..."
  $DOCKER build -q -t "$IMAGE-$name" --build-arg BASE_IMAGE="$base_image" \
    -f "$SCRIPT_DIR/docker/remote-kms-provisioning.Dockerfile" "$SCRIPT_DIR/docker"
  $DOCKER run --rm -v "$ROOT_DIR:/drivers-tools:ro" "$IMAGE-$name" bash -c '
    set -e
    sudo apt-get -qq update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq \
      -o DPkg::Lock::Timeout=-1 install python3 python3-pip git < /dev/null > /dev/null
    if python3 -m venv --clear /tmp/probe > /dev/null 2>&1; then
      echo "expected no working venv module; this test is no longer testing anything" >&2
      exit 1
    fi
    cp -r /drivers-tools ~/drivers-tools
    cd ~/drivers-tools
    . .evergreen/ensure-uv.sh
    ensure_uv
    uv --version
  '
  echo "Testing ensure_uv without the venv module ($base_image) ... done."
}

# ensure_uv called from an active virtual environment, which is how the Node OIDC
# tests invoke it. pip is present there, but pip refuses `--user` inside a venv, so
# the venv fallback is the only way through, and it has to build its venv using a
# venv's own interpreter. Neither of the cases above covers that.
test_inside_active_venv() {
  local name="$1" base_image="$2"
  echo "Testing ensure_uv inside an active venv ($base_image) ..."
  $DOCKER build -q -t "$IMAGE-$name" --build-arg BASE_IMAGE="$base_image" \
    -f "$SCRIPT_DIR/docker/remote-kms-provisioning.Dockerfile" "$SCRIPT_DIR/docker"
  $DOCKER run --rm -v "$ROOT_DIR:/drivers-tools:ro" "$IMAGE-$name" bash -c '
    set -e
    sudo apt-get -qq update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq \
      -o DPkg::Lock::Timeout=-1 install python3 python3-pip python3-venv git < /dev/null > /dev/null
    python3 -m venv ~/outer
    . ~/outer/bin/activate
    # Guard both halves of what makes this case distinct, so it cannot quietly
    # stop testing anything: pip has to be present, and --user has to be refused.
    python3 -m pip --version > /dev/null
    if python3 -m pip install --user -q uv > /dev/null 2>&1; then
      echo "expected --user to be refused inside a venv" >&2
      exit 1
    fi
    cp -r /drivers-tools ~/drivers-tools
    cd ~/drivers-tools
    . .evergreen/ensure-uv.sh
    ensure_uv
    uv --version
    case "$(command -v uv)" in
    *drivers-tools-uv-venv*) ;;
    *) echo "expected uv from the fallback venv, got $(command -v uv)" >&2; exit 1 ;;
    esac
  '
  echo "Testing ensure_uv inside an active venv ($base_image) ... done."
}

# Keep these in sync with the defaults in create-and-setup-instance.sh
# (GCPKMS_IMAGEFAMILY) and create-and-setup-vm.sh (AZUREKMS_IMAGE).
test_provisioning gcpkms .evergreen/csfle/gcpkms/remote-scripts/setup-gce-instance.sh debian:11
test_provisioning azurekms .evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh debian:11

# debian:11 matches both defaults above. ubuntu:20.04 is a supported
# AZUREKMS_IMAGE (see azurekms/README.md) and additionally covers a system
# interpreter whose bundled pip predates PEP 600.
test_no_system_pip nopip-debian11 debian:11
test_no_system_pip nopip-ubuntu2004 ubuntu:20.04

# debian:11 matches the Evergreen image whose missing python3-venv this covers.
test_no_venv_module novenv-debian11 debian:11

test_inside_active_venv invenv-debian11 debian:11
