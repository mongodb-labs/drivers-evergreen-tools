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
    . $DRIVERS_TOOLS/.evergreen/secrets_handling/setup-secrets.sh drivers/gke
fi

# Ensure required binaries.
. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh gcloud
. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl

# Handle kubectl credentials.
GKE_KEYFILE=/tmp/testgke_key_file.json
echo ${GKE_KEYFILE_CONTENT} | base64 --decode > $GKE_KEYFILE
# Set 600 permissions on private key file. Otherwise ssh / scp may error with permissions "are too open".
chmod 600 $GKE_KEYFILE
gcloud auth activate-service-account --key-file $GKE_KEYFILE
gcloud components install --quiet gke-gcloud-auth-plugin
gcloud container clusters get-credentials $GKE_CLUSTER_NAME --region ${GKE_REGION} --project $GKE_PROJECT

# Create the pod with a random name.
POD_NAME="test-gke-$RANDOM"
echo "export K8S_POD_NAME=$POD_NAME" >> ./secrets-export.sh
export K8S_POD_NAME=$POD_NAME

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: default
  labels:
    app: test-pod
spec:
  containers:
  - name: debian
    image: debian:12
    resources:
      limits:
        memory: "4Gi"
        cpu: "1"
        ephemeral-storage: "1Gi"
    command: ["/bin/sleep", "3650d"]
    imagePullPolicy: IfNotPresent
  nodeSelector:
    kubernetes.io/os: linux
EOF

# Set up the pod - run directly so PATH is passed in.
bash $DRIVERS_TOOLS/.evergreen/k8s/configure-pod.sh ${POD_NAME}

popd
