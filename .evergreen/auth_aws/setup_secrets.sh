#!/usr/bin/env bash
# setup_secrets
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

# TODO: Remove this file after DRIVERS-2585
echo "auth_aws/setup_secrets.sh is deprecated, please use auth_aws/setup-secrets.sh"
. $SCRIPT_DIR/../secrets_handling/setup-secrets.sh "$@"
