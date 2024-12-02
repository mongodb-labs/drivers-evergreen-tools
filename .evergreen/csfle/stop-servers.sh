#!/usr/bin/env bash

# Clean up CSFLE kmip servers
set -e

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
rm -f pykmip.db
if [ -f "kmip_pids.pid" ]; then
  while read p; do
    kill -9 "$p" || true
  done <kmip_pids.pid
  rm kmip_pids.pid
fi

popd
