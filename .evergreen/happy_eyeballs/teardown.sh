#!/usr/bin/env bash

# Clean up oscp server
set -e

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Ensure uv is available here.
. ../ensure-uv.sh
ensure_uv || exit 1

uv run python server.py --stop "$@"

popd
