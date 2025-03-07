#!/usr/bin/env bash

# Clean up oscp server
set -e

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
if [ -f "ocsp.pid" ]; then
  echo "Killing ocsp server..."
  < ocsp.pid xargs kill -15 || true
  rm ocsp.pid
  echo "Killing ocsp server...done."
fi
popd
