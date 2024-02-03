#!/usr/bin/env bash
# setup_secrets
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/../auth_aws
. ./activate-authawsvenv.sh
popd
set -x
echo "Getting secrets:" "$@"
python $SCRIPT_DIR/../auth_aws/setup_secrets.py "$@"
echo "Got secrets"
