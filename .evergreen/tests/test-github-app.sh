#!/usr/bin/env bash

# Test basic github app setup.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $DRIVERS_TOOLS/.evergreen/github_app
. utils.sh
bootstrap
bash get-access-token.sh drivers-evergreen-tools mongodb-labs > /dev/null
popd

make -C ${DRIVERS_TOOLS} test
