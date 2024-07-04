#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

VARLIST=(
K8S_DRIVERS_TAR_FILE
K8S_VARIANT
K8S_TEST_CMD
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in ${VARLIST[*]}; do
[[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Set the current K8S_VARIANT.
echo "K8S_VARIANT=$K8S_VARIANT" >> secrets-export.sh
VARIANT=$(echo "$K8S_VARIANT" | tr '[:upper:]' '[:lower:]')
VARIANT_DIR=$DRIVERS_TOOLS/.evergreen/k8s/$VARIANT

# Set up the pod.
echo "Setting up $VARIANT pod..."
. $VARIANT_DIR/setup.sh
echo "Setting up $VARIANT pod... done."

# Extract the tar file to the /tmp/test directory.
echo "Setting up driver test files..."
kubectl exec ${K8S_POD_NAME} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
tar cf - ${K8S_DRIVERS_TAR_FILE} | kubectl exec -i ${K8S_POD_NAME} -- /bin/sh -c 'tar xf - -C /tmp/test'
echo "Setting up driver test files... done."

# Run the command.
echo "Running the driver test command..."
kubectl exec ${K8S_POD_NAME} -- bash -c "cd /tmp/test && ${K8S_TEST_CMD}"
echo "Running the driver test command... done."

# Tear down the pod.
echo "Tearding down $VARIANT pod..."
. $VARIANT_DIR/teardown.sh
echo "Tearding down $VARIANT pod... done."

popd
