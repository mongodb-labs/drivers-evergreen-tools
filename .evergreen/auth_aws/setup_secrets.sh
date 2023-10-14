#!/usr/bin/env bash
# setup_secrets
set -eu

HERE=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
if [ "Windows_NT" = "$OS:-" ]; then
    HERE=$(cygpath $HERE)
fi
pushd $HERE
. ./activate-authawsvenv.sh
popd
echo "Getting secrets:" "$@"
python $HERE/setup_secrets.py "$@"
echo "Got secrets"
