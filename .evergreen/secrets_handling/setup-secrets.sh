#!/usr/bin/env bash
# Secrets setup script.  It will write the secrets into the calling
# directory as `secrets-export.sh`.
#
# Run with a . to add environment variables to the current shell:
#
# . ../secrets_handling/setup-secrets.sh drivers/<vault_name>
#
# More than one vault can be provided as extra arguments.
# All of the variables will be written to the same file.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/../auth_aws
. ./activate-authawsvenv.sh
popd
set -x
echo "Getting secrets:" "$@"
python $SCRIPT_DIR/setup_secrets.py "$@"
source $(pwd)/secrets-export.sh
echo "Got secrets"
