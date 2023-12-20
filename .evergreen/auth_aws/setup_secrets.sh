#!/usr/bin/env bash
# setup_secrets
# See https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets
# for details on usage.
set -eu

CURRENT=$(pwd)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

. ./activate-authawsvenv.sh
set -x
echo "Getting AWS secrets:" "$@"
python ./setup_secrets.py "$@"
mv secrets-export.sh $CURRENT
popd
echo "Got secrets"
