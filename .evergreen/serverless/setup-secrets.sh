#!/usr/bin/env bash
#
# setup-secrets.sh
#
# Set up serverless secrets using Drivers AWS Secrets Manager.
# Writes a secrets-export.sh file to this folder.
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

VAULT_NAME="${1:-serverless}"
bash ../auth_aws/setup_secrets.sh drivers/$VAULT_NAME
popd