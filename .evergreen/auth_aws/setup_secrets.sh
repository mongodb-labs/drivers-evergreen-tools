#!/usr/bin/env bash
# setup_secrets
# See https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets
# for details on usage.
set -eu

HERE=$(dirname $0)

pushd $HERE
. ./activate-authawsvenv.sh
popd
echo "Getting secrets:" "$@"
python $HERE/setup_secrets.py "$@"
echo "Got secrets"
