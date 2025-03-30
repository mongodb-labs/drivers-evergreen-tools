#!/usr/bin/env bash
#
# Tear down docker-releated assets.
#
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

# Find the appropriate docker command.
if command -v podman &> /dev/null; then
    DOCKER="sudo podman"
else
    DOCKER=docker
fi
if ! command -v $DOCKER &> /dev/null; then
    exit 0
fi

# Kill all containers.
$DOCKER rm "$($DOCKER ps -a -q)" &> /dev/null || true

# Remove all images.
$DOCKER rmi -f "$($DOCKER -a -q)" &> /dev/null || true

# Remove all generated files in this subfolder.
pushd $SCRIPT_DIR > /dev/null

if command -v sudo &> /dev/null; then
    sudo git clean -dffx
else
    git clean -dffx
fi

popd > /dev/null
