#!/usr/bin/env bash
# setup secrets for atlas testing.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
VAULT_NAME="${1:-atlas-dev}"
. $SCRIPT_DIR/../secrets_handling/setup-secrets.sh drivers/$VAULT_NAME
popd
