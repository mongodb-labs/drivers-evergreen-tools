#!/usr/bin/env bash

# Clean up CSFLE kmip servers
set -e

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
rm -f pykmip.db
if [ -f "kmip_pids.pid" ]; then
  while read p; do
    kill "$p" -9
  done <kmip_pids.txt
fi
popd
