#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

python3 $SCRIPT_DIR/orchestration/drivers_orchestration.py clean

pushd $DRIVERS_TOOLS > /dev/null
find . -type f -name '*.log' -exec rm {} \;
rm -rf "$${TMPDIR:-$${TEMP:-$${TMP:-/tmp}}}"/mongo*
find . -type f -name '*.env' -exec rm {} \;
find . -type f -name '*results.json' -exec rm {} \;

popd > /dev/null
