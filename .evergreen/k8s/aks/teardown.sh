#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f $SCRIPT_DIR/secrets-export.sh ]; then
  echo "Sourcing secrets"
  source $SCRIPT_DIR/secrets-export.sh
fi

# The credentials and kubeconfig are only needed when there is a pod to
# delete; AKS_SERVICE_ACCOUNT_NAMESPACE is guaranteed recorded when the pod
# is (both come from the same vault write).
DELETE_POD="$SCRIPT_DIR/../delete-pod.sh"
if [ -n "${K8S_POD_NAME:-}" ]; then
  az aks get-credentials --overwrite-existing -n "${AKS_CLUSTER_NAME}" -g "${AKS_RESOURCE_GROUP}"
  # Sourced: it overwrites SCRIPT_DIR, so resolve the helper path above first.
  . $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
fi
bash "$DELETE_POD" aks "${AKS_SERVICE_ACCOUNT_NAMESPACE:-}"
