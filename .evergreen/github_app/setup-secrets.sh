#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR > /dev/null
VAULT=${1:-drivers/comment-bot}
. $SCRIPT_DIR/../secrets_handling/setup-secrets.sh $VAULT
popd > /dev/null
