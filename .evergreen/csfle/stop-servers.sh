#!/usr/bin/env bash

# Clean up CSFLE kmip servers
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
if [ -f "kmip_pids.pid" ]; then
  while read p; do
    kill -9 "$p" 2> /dev/null || true
  done <kmip_pids.pid
  rm kmip_pids.pid
fi
rm -f pykmip.db

popd
