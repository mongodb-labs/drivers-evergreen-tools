#!/usr/bin/env bash
# setup secrets for csfle testing.
set -eu

CURRENT=$(pwd)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR
bash ../auth_aws/setup_secrets.sh drivers/csfle
source secrets-export.sh

. ./activate-kmstlsvenv.sh
python ./setup_secrets.py

cp secrets-export.sh $CURRENT
