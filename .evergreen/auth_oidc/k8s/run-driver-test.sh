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

# Set up the pod.
bash ./.evergreen/setup-pod.sh $VARIANT

# Read in the secrets.
source ./../../k8s/$VARIANT/secrets-export.sh

# Extract the tar file to the /tmp/test directory.
bash ./../../ensure-binary.sh kubectl
kubectl exec ${K8S_POD_NAME} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
tar cf - ${K8S_DRIVERS_TAR_FILE} | kubectl exec -i ${K8S_POD_NAME} -- /bin/sh -c 'tar xf - -C /tmp/test'

# Run the command.
kubectl exec ${K8S_POD_NAME} -- bash -c "cd /tmp/test && ${K8S_TEST_CMD}"

popd
