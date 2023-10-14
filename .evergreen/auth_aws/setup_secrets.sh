#!/usr/bin/env bash
# setup_secrets
set -eu

HERE=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

pushd $HERE
. ./activate-authawsvenv.sh
popd
echo "Getting secrets:" "$@"
target=$HERE/setup_secrets.py
if [ "Windows_NT" = "$OS" ]; then
    target=$(cygpath $target)
fi
python $target "$@"
echo "Got secrets"
