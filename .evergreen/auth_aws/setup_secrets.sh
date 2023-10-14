#!/usr/bin/env bash
# setup_secrets
set -eu

HERE=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
pushd $HERE
. ./activate-authawsvenv.sh
popd
set -x
echo "Getting secrets:" "$@"
which python
python $HERE/setup_secrets.py "$@"
echo "Got secrets"
