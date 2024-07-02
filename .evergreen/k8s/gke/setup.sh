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
if [ -z "${AZUREKMS_TENANTID:-}" ]; then
    . $DRIVERS_TOOLS/.evergreen/secrets_handling/setup-secrets.sh drivers/gke
fi

# Get binaries
bash $DRIVERS_TOOLS/.evergreen/ensure-binary.sh gcloud
bash $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl

# Handle kubectl credentials.
export GCPKMS_KEYFILE_CONTENT=$GKE_KEYFILE_CONTENT
bash $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/login.sh
gcloud container clusters get-credentials $GKE_CLUSTER_NAME --region $GKE_REGION --project $GKE_PROJECT

# Create the pod with a random name.
set -x
POD_NAME="test-$RANDOM"
echo "export K8S_POD_NAME=$POD_NAME" >> ./secrets-export.sh

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: default
spec:
  containers:
  - name: debian
    image: debian:11
    command: ["/bin/sleep", "3650d"]
    imagePullPolicy: IfNotPresent
  nodeSelector:
    kubernetes.io/os: linux
EOF

# Set up the pod.
bash $DRIVERS_TOOLS/.evergreen/k8s/setup-pod.sh ${POD_NAME}

popd
