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

# Read in the secrets.
VARIANT=$(echo "$K8S_VARIANT" | tr '[:upper:]' '[:lower:]')
source ./../../k8s/$VARIANT/secrets-export.sh

# Extract the tar file to the /tmp/test directory.
. ../../k8s/download-kubectl.sh
$KUBECTL exec ${K8S_POD_NAME} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
tar cf - ${K8S_DRIVERS_TAR_FILE} | $KUBECTL exec -i ${K8S_POD_NAME} -- /bin/sh -c 'tar xf - -C /tmp/test'

# Run the command.
$KUBECTL exec ${K8S_POD_NAME} -- bash -c "cd /tmp/test && ${K8S_TEST_CMD}"
