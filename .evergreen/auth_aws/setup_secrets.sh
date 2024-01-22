#!/usr/bin/env bash
# setup_secrets
# See https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets
# for details on usage.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR
. ./activate-authawsvenv.sh
popd
set -x
echo "Getting secrets:" "$@"
python $SCRIPT_DIR/setup_secrets.py "$@"
echo "Got secrets"
