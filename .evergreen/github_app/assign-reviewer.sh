#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Bootstrap the app.
source utils.sh
bootstrap

# Run the app.
node assign-reviewer.mjs "$@"
popd
