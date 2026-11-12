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

# Verify tags when requested: the policy covers the pre-provisioned cluster
# the tests run on, not only what this script creates.
if [ -n "${VERIFY_MONGODB_TAGS:-}" ]; then
  . "$SCRIPT_DIR"/verify-aks-setup.sh
  verify_aks_tags
fi

# Create the pod with a random name.
POD_NAME="test-aks-$RANDOM"
# Persist the effective settings with the pod name: teardown may run in a
# shell that does not inherit this environment (the group backstop), and an
# env-based setup skips the vault write that would otherwise record them.
cat <<EOF >> ./secrets-export.sh
export AKS_CLUSTER_NAME=${AKS_CLUSTER_NAME}
export AKS_RESOURCE_GROUP=${AKS_RESOURCE_GROUP}
export AKS_SERVICE_ACCOUNT_NAMESPACE=${AKS_SERVICE_ACCOUNT_NAMESPACE}
export K8S_POD_NAME=$POD_NAME
EOF
export K8S_POD_NAME=$POD_NAME

. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${AKS_SERVICE_ACCOUNT_NAMESPACE}
  labels:
    azure.workload.identity/use: "true"
    app: test-pod
spec:
  serviceAccountName: ${AKS_SERVICE_ACCOUNT_NAME}
  containers:
  - name: debian
    image: debian:12
    command: ["/bin/sleep", "3650d"]
    imagePullPolicy: IfNotPresent

  nodeSelector:
    kubernetes.io/os: linux
EOF

# Set up the pod.
bash $DRIVERS_TOOLS/.evergreen/k8s/configure-pod.sh ${POD_NAME}

popd
