#!/usr/bin/env bash

# Clean up oscp server
set -e

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
if [ -f "ocsp.pid" ]; then
  < ocsp.pid xargs kill -9 || true
  rm ocsp.pid
fi
popd
