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

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

source secrets-export.sh
source $K8S_VARIANT_DIR/secrets-export.sh

# Extract the tar file to the /tmp/test directory.
echo "Setting up driver test files..."
kubectl exec ${K8S_POD_NAME} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
kubectl cp ${K8S_DRIVERS_TAR_FILE} ${K8S_POD_NAME}:/tmp/drivers-test.tgz
kubectl exec ${K8S_POD_NAME} -- bash -c "cd /tmp && tar -xf drivers-test.tgz -C test"
echo "Setting up driver test files... done."

# Run the command.
echo "Running the driver test command..."
kubectl cp ./secrets-export.sh ${K8S_POD_NAME}:/tmp/test/secrets-export.sh

# Temporarily disable `set -e` for this command to capture the exit code
set +e
kubectl exec ${K8S_POD_NAME} -- bash -c "cd /tmp/test && source secrets-export.sh && ${K8S_TEST_CMD}"
EXIT_CODE=$?  # Capture the exit code
set -e  # Re-enable `set -e`
if [ $EXIT_CODE -ne 0 ]; then
   if [ $EXIT_CODE -eq 137 ]; then
      echo -e "\n ERROR: Pod process was OOMKilled (Exit Code 137).\n"
   else
      echo -e "\n ERROR: Pod process failed with exit code $EXIT_CODE.\n"
   fi

    echo -e "\n Pod description:\n"
    # Print pod details
    kubectl describe pod ${K8S_POD_NAME}
    echo -e "\n Pod logs:\n"
    # Print pod logs (current still active or previous pod)
    kubectl logs ${K8S_POD_NAME} || kubectl logs -p ${K8S_POD_NAME}
    exit $EXIT_CODE
fi
echo "Running the driver test command... done."
popd
