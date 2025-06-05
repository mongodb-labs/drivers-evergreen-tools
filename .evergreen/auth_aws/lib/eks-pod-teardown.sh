#!/usr/bin/env bash
set -eu

EKS_APP_NAME=$1

echo "Tearing down EKS assets..."
. ../../ensure-binary.sh kubectl
kubectl delete deployment $EKS_APP_NAME
kubectl delete services $EKS_APP_NAME
bash ../../k8s/eks/teardown.sh
echo "Tearing down EKS assets... done."
