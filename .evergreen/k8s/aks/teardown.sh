#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f $SCRIPT_DIR/secrets-export.sh ]; then
  echo "Sourcing secrets"
  source $SCRIPT_DIR/secrets-export.sh
fi

if [ -z "${K8S_POD_NAME:-}" ]; then
  echo "Skipping aks pod teardown: no pod was created (K8S_POD_NAME is not set)."
else
  az aks get-credentials --overwrite-existing -n "${AKS_CLUSTER_NAME}" -g "${AKS_RESOURCE_GROUP}"
  . $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
  # Name the pod's namespace explicitly: the kubeconfig's current namespace
  # is not where setup.sh created it, and --ignore-not-found would turn a
  # wrong-namespace lookup into reported success while the pod keeps running.
  kubectl delete pod ${K8S_POD_NAME} --namespace "${AKS_SERVICE_ACCOUNT_NAMESPACE}" --ignore-not-found
fi
