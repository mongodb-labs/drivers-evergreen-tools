#!/usr/bin/env bash
#
# This script tears down Atlas Data Lake tests.
#
set -eu

if command -v podman &> /dev/null; then
    DOCKER="podman --storage-opt ignore_chown_errors=true"
else
    DOCKER=docker
fi
$DOCKER kill atlas-data-lake || true
$DOCKER rm atlas-data-lake
