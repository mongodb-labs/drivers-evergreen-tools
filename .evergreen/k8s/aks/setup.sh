#!/usr/bin/env bash

set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -z "${DRIVER_NAME:-}" ]; then
    echo "Must set DRIVER_NAME!"
    exit 1
fi

pushd $SCRIPT_DIR

# Handle secrets from vault.
if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${AZUREKMS_TENANTID:-}" ]; then
    . ./../../secrets_handling/setup-secrets.sh drivers/aks
fi

# Login.
"$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/login.sh

az aks get-credentials --overwrite-existing -n "${AKS_CLUSTER_NAME}" -g "${AKS_RESOURCE_GROUP}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${DRIVER_NAME}-test
  namespace: ${AKS_SERVICE_ACCOUNT_NAMESPACE}
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: ${AKS_SERVICE_ACCOUNT_NAME}
  containers:
  - name: debian
    image: debian:11
    command: ["/bin/sleep", "3650d"]
    imagePullPolicy: IfNotPresent

  nodeSelector:
    kubernetes.io/os: linux
EOF
