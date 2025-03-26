#!/usr/bin/env bash

# Clean up oscp server
set -e

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Ensure python3 here
. ../find-python3.sh

PYTHON="$(ensure_python3 2>/dev/null)"
if [ -z "${PYTHON}" ]; then
  # For debug purposes
  find_python3
  exit 1
fi

$PYTHON server.py --stop "$@"

popd
