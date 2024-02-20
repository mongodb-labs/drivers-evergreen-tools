#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

# TODO: Remove this file after merging
# https://github.com/mongodb/mongo-python-driver/pull/1517 and
# https://github.com/mongodb/mongo-go-driver/pull/1564
. $SCRIPT_DIR/./await-servers.sh "$@"
