#!/usr/bin/env bash

# Clean up CSFLE kmip servers
set -e

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
rm -f pykmip.db
if [ -f "kmip_pids.pid" ]; then
  < kmip_pids.pid xargs kill -9 || true
  rm kmip_pids.pid
fi
popd

# Forcibly kill the process listening on the desired ports, most likely
# left running from a previous task.
. "$SCRIPT_DIR/../process-utils.sh"
for port in 5698 9000 9001 9002 8080; do
  killport $port 9
done
