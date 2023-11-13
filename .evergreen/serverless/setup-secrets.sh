#!/usr/bin/env bash
#
# setup-secrets.sh
#
# Set up serverless secrets using Drivers AWS Secrets Manager.
# Writes a secrets-export.sh file to this folder.
set -eux

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR
bash ../auth_aws/setup_secrets.sh drivers/serverless
