#!/usr/bin/env bash
# setup-secrets for AWS testing.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
. $SCRIPT_DIR/../secrets_handling/setup-secrets.sh drivers/aws_auth
popd
