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

# Verify the cluster's tags when requested: the policy covers the
# pre-provisioned cluster the tests run on, not only what this script creates.
if [ -n "${VERIFY_MONGODB_TAGS:-}" ]; then
  CLUSTER_TAGS=$(az aks show --name "${AKS_CLUSTER_NAME}" --resource-group "${AKS_RESOURCE_GROUP}" --query tags --output json)
  . "$DRIVERS_TOOLS"/.evergreen/verify-tags.sh
  verify_cloud_tags "AKS cluster ${AKS_CLUSTER_NAME}" "${CLUSTER_TAGS}"
fi

# Create the pod with a random name.
POD_NAME="test-aks-$RANDOM"
echo "export K8S_POD_NAME=$POD_NAME" >> ./secrets-export.sh
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
