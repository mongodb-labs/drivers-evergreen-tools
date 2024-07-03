#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Handle secrets from vault.
if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${AZUREKMS_TENANTID:-}" ]; then
    . ./../../secrets_handling/setup-secrets.sh drivers/aks
fi

# Handle credentials.
. $DRIVERS_TOOLS/.evergreen/csfle/azurekms/login.sh
az aks get-credentials --overwrite-existing -n "${AKS_CLUSTER_NAME}" -g "${AKS_RESOURCE_GROUP}"

# Create the pod with a random name.
POD_NAME="test-$RANDOM"
echo "export K8S_POD_NAME=$POD_NAME" >> ./secrets-export.sh
. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
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

# Set up the pod.
bash $DRIVERS_TOOLS/.evergreen/k8s/configure-pod.sh ${POD_NAME}

popd
