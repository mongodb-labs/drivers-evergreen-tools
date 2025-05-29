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

# Tear down the eks deployment and pod if necessary.
source ./test-env.sh

if [ -n "${EKS_APP_NAME:-}" ]; then
  echo "Tearing down EKS assets..."
  . $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
  set -x
  kubectl delete deployment $EKS_APP_NAME
  kubectl delete services $EKS_APP_NAME
  bash $DRIVERS_TOOLS/.evergreen/k8s/eks/teardown.sh
  echo "Tearing down EKS assets... done."
fi

popd >/dev/null

echo "Tearing down auth_aws.. done."
