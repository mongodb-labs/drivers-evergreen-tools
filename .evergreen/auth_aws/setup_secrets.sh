#!/usr/bin/env bash
# setup_secrets
set -eu

HERE=DIR="$(dirname "${BASH_SOURCE[0]}")"

pushd $HERE
. ./activate-authawsvenv.sh
popd
echo "Getting secrets:" "$@"
python $HERE/setup_secrets.py "$@"
echo "Got secrets"
