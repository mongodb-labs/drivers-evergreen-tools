#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

if [ -z "${K8S_VARIANT:-}" ]; then
    echo "Must set K8S_VARIANT!"
    exit 1
fi

# Set the current K8S_VARIANT.
echo "K8S_VARIANT=$K8S_VARIANT" >> secrets-export.sh
VARIANT=$(echo "$K8S_VARIANT" | tr '[:upper:]' '[:lower:]')
VARIANT_DIR=$DRIVERS_TOOLS/.evergreen/k8s/$VARIANT

# Set up the pod.
echo "Setting up $VARIANT pod..."
. $VARIANT_DIR/setup.sh
echo "Setting up $VARIANT pod... done."

# Run the self test.
echo "Running self test on $VARIANT..."
kubectl exec ${POD_NAME} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
kubectl cp ./remote-scripts/run-self-test.sh ${POD_NAME}:/tmp/test/run-self-test.sh
kubectl cp ./remote-scripts/test.py ${POD_NAME}:/tmp/test/test.py
kubectl cp ./secrets-export.sh ${POD_NAME}:/tmp/test/secrets-export.sh
kubectl exec ${POD_NAME} -- /tmp/test/run-self-test.sh
echo "Running self test on $VARIANT... done."

# Tear down the pod.
echo "Tearding down $VARIANT pod..."
. $VARIANT_DIR/teardown.sh
echo "Tearding down $VARIANT pod... done."

popd
