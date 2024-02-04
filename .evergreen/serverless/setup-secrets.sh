#!/usr/bin/env bash
#
# setup-secrets.sh
#
# Set up serverless secrets using Drivers AWS Secrets Manager.
# Writes a secrets-export.sh file to this folder.
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

VAULT_NAME="${1:-serverless}"
pushd $SCRIPT_DIR
. ../secrets_handling/setup-secrets.sh drivers/$VAULT_NAME
popd
