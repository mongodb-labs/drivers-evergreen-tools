#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR

# If we've gotten credentials, ensure the instance profile is set.
if [ -f secrets-export.sh ]; then
  . ./activate-authawsvenv.sh
  echo "SOURCING SECRETS!"
  source secrets-export.sh
  python ./lib/aws_assign_instance_profile.py
fi

popd
