#!/usr/bin/env bash
#
# Start an OIDC-enabled server on a kubernetes pod.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

source secrets-export.sh
source $K8S_VARIANT_DIR/secrets-export.sh

# Extract the tar file to the /tmp/test directory.
echo "Setting up server on ${K8S_POD_NAME}..."
kubectl exec ${K8S_POD_NAME} -- bash -c "rm -rf /tmp/server && mkdir -p /tmp/server/drivers-tools"
K8S_TAR_FILE=/tmp/drivers-tools.tgz
pushd $DRIVERS_TOOLS
git archive -o $K8S_TAR_FILE HEAD
popd
tar cf - ${K8S_TAR_FILE} | kubectl exec -i ${K8S_POD_NAME} -- /bin/sh -c 'tar xf - -C /tmp/server/drivers-tools'
kubectl cp $K8S_VARIANT_DIR/secrets-export.sh ${K8S_POD_NAME}:/tmp/server/secrets-export.sh
kubectl cp ./remote-scripts/start-server.sh ${K8S_POD_NAME}:/tmp/server/start-server.sh
kubectl exec ${K8S_POD_NAME} -- /tmp/server/start-server.sh
echo "Setting up server on ${K8S_POD_NAME}... done."

popd
