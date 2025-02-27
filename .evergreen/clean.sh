#!/usr/bin/env bash
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh


pushd $DRIVERS_TOOLS > /dev/null
rm -rf $MONGODB_BINARIES
rm -rf ./mongodb mo-expansion* mongo_crypt_v1* uri.txt
find . -type f -name '*.log' -exec rm {} \;
rm -rf "$${TMPDIR:-$${TEMP:-$${TMP:-/tmp}}}"/mongo*

if [ "${1:-}" == "all" ]; then
  find . -type f -name '*.env' -exec rm {} \;
  find . -type f -name '*result.json' -exec rm {} \;
fi

popd > /dev/null
