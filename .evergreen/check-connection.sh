#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

if [ ! -f "${MONGODB_BINARIES}/mongosh" ]; then
    bash -c "source ${DRIVERS_TOOLS}/.evergreen/download-mongodb.sh && download_and_extract_mongosh"
fi

MONGODB_URI=${MONGODB_URI:-"mongodb://127.0.0.1:27017/?serverSelectionTimeoutMS=10000"}
MONGOSH_EXTRA_ARGS=${MONGOSH_EXTRA_ARGS:-}
# MONGOSH_EXTRA_ARGS is deliberately left unquoted so callers can pass several
# arguments (e.g. TLS options) in a single variable.
# shellcheck disable=SC2086
${MONGODB_BINARIES}/mongosh "${MONGODB_URI}" ${MONGOSH_EXTRA_ARGS} --eval "db.runCommand({\"ping\":1})"
