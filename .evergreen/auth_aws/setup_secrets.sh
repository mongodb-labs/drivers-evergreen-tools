#!/usr/bin/env bash
# setup_secrets
# See https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets
# for details on usage.
set -eu

CURRENT=$(pwd)
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
. $DIR/../handle-paths.sh
pushd $DIR

. ./activate-authawsvenv.sh
set -x
echo "Getting secrets:" "$@"
python ./setup_secrets.py "$@"
mv secrets-export.sh $CURRENT
popd
echo "Got secrets"
