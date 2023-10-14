#!/usr/bin/env bash
# setup_secrets
set -eu

HERE=$(dirname $0)

pushd $HERE
. ./activate-authawsvenv.sh
popd
set -x
echo "Getting secrets:" "$@"
echo "hello $(which python)"
python $HERE/setup_secrets.py "$@"
echo "Got secrets"
