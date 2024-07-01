#!/usr/bin/env bash

set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

if [ ! -f "${MONGODB_BINARIES}/mongosh" ]; then
    bash -c "source ${DRIVERS_TOOLS}/.evergreen/download-mongodb.sh && download_and_extract_mongosh"
fi

MONGODB_URI=${MONGODB_URI:-""}
${MONGODB_BINARIES}/mongosh "${MONGODB_URI}" --eval "db.runCommand({\"ping\":1})" --&serverSelectionTimeoutMS=10000
