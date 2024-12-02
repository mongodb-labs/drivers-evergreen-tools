#!/usr/bin/env bash

# Clean up CSFLE kmip servers
set -e

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
rm -f pykmip.db
if [ -f "kmip_pids.pid" ]; then
  while read p; do
    echo "Killing process $p"
    kill "$p" -SIGKILL
  done <kmip_pids.pid
fi
popd
