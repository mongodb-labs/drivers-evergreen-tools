#!/usr/bin/env bash

# Test mongodl and mongosh_dl.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $DRIVERS_TOOLS/.evergreen > /dev/null

for v in 3.6 4.0; do
  export MONGODB_VERSION=$v
  URI=$(bash run-orchestration.sh)
  $MONGODB_BINARIES/mongosh $URI --eval "db.runCommand({\"ping\":1})"
  bash stop-orchesration.sh
done

popd
make -C ${DRIVERS_TOOLS} test
