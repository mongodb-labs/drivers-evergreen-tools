#!/usr/bin/env bash
# setup_secrets
# See https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets
# for details on usage.
set -eu

DIR=$(dirname ${BASH_SOURCE:-$0})
. $DIR/../handle-paths.sh

. ./activate-authawsvenv.sh
set -x
echo "Getting secrets:" "$@"
python $DIR/setup_secrets.py "$@"
echo "Got secrets"
