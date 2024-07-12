#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

VARLIST=(
K8S_DRIVERS_TAR_FILE
K8S_TEST_CMD
)

source secrets-export.sh
source $K8S_VARIANT_DIR/secrets-export.sh

# Extract the tar file to the /tmp/test directory.
echo "Setting up driver test files..."
kubectl exec ${K8S_POD_NAME} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
tar cf - ${K8S_DRIVERS_TAR_FILE} | kubectl exec -i ${K8S_POD_NAME} -- /bin/sh -c 'tar xf - -C /tmp/test'
echo "Setting up driver test files... done."

# Run the command.
echo "Running the driver test command..."
kubectl exec ${K8S_POD_NAME} -- bash -c "cd /tmp/test && ${K8S_TEST_CMD}"
echo "Running the driver test command... done."

popd
