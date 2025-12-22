#!/usr/bin/env bash

# Test mongodl and mongosh_dl.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $DRIVERS_TOOLS/.evergreen

for v in 3.6 4.0; do
  export MONGODB_VERSION=$v
  TOPOLOGY=standalone bash run-tests.sh
  TOPOLOGY=replica_set SSL=ssl bash run-tests.sh
  TOPOLOGY=sharded_cluster AUTH=auth SSL=ssl bash run-tests.sh
done

popd
