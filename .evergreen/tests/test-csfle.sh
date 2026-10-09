#!/usr/bin/env bash

# Test csfle
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/../csfle

# The interpreter is uv-managed (the lock resolves for all of Python 3.9-3.14
# through resolution markers), so one setup run covers every supported version.
bash ./setup.sh
bash ./teardown.sh

popd
