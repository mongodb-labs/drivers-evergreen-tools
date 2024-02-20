#!/usr/bin/env bash

# Clean up CSFLE kmip servers
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
rm -f pykmip.db
if [ -f "kmip_pids.pid" ]; then
  < kmip_pids.pid xargs kill -9 || true
  rm kmip_pids.pid
fi
popd
