#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail
set -x

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

VARIANT=$1
if [ -z "$VARIANT" ]; then
    echo "Must supply a variant as the first argument!"
    exit 1
fi

echo "Setting up the $VARIANT pod..."
bash ./../../k8s/$VARIANT/setup.sh

echo "Copying the test files to the pod..."
source ./../../k8s/$VARIANT/secrets-export.sh
. ../../k8s/download-kubectl.sh
$KUBECTL cp ./remote-scripts/run-self-test.sh ${K8S_POD_NAME}:/tmp/run-self-test.sh
$KUBECTL cp ./remote-scripts/test.py ${K8S_POD_NAME}:/tmp/test.py
$KUBECTL cp ./secrets-export.sh ${K8S_POD_NAME}:/tmp/secrets-export.sh

echo "Running the self test on the pod..."
$KUBECTL exec ${K8S_POD_NAME} -- bash /tmp/run-self-test.sh

popd
