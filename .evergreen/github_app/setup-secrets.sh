#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR > /dev/null
. $SCRIPT_DIR/../secrets_handling/setup-secrets.sh drivers/comment-bot
popd > /dev/null
