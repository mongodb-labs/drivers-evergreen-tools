#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR > /dev/null

. $SCRIPT_DIR/../secrets_handling/setup-secrets.sh drivers/comment-bot

BIN_DIR="bin"
mkdir -p $BIN_DIR
go build -o $BIN_DIR/perfcomp ./cmd/perfcomp/

popd > /dev/null
