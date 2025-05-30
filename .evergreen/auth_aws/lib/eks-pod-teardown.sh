#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

EKS_APP_NAME=$1

echo "Tearing down EKS assets..."
. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
kubectl delete deployment $EKS_APP_NAME
kubectl delete services $EKS_APP_NAME
bash $DRIVERS_TOOLS/.evergreen/k8s/eks/teardown.sh
echo "Tearing down EKS assets... done."
