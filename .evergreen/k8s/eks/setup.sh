#!/usr/bin/env bash

set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Handle secrets from vault.
if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${EKS_CLUSTER_NAME:-}" ]; then
    . ./../../secrets_handling/setup-secrets.sh drivers/eks
fi

# Set up kubectl creds.
. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
aws eks update-kubeconfig --region $EKS_REGION --name $EKS_CLUSTER_NAME

# Create the pod with a random name.
POD_NAME="test-eks-$RANDOM"
echo "export K8S_POD_NAME=$POD_NAME" >> ./secrets-export.sh
export K8S_POD_NAME=$POD_NAME

. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: default
spec:
  serviceAccountName: ${EKS_SERVICE_ACCOUNT_NAME}
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
