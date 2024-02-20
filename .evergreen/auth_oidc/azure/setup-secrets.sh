#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail
set -x

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR
. ../../secrets_handling/setup-secrets.sh drivers/azureoidc
popd
