#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

echo "Tearing down auth_aws..."
pushd $SCRIPT_DIR >/dev/null

# If we've gotten credentials, ensure the instance profile is set.
if [ -f secrets-export.sh ]; then
  . ./activate-authawsvenv.sh
  source secrets-export.sh
  python ./lib/aws_assign_instance_profile.py || true
fi

popd >/dev/null

echo "Tearing down auth_aws.. done."
