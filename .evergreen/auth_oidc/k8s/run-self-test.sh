#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

source secrets-export.sh
source $K8S_VARIANT_DIR/secrets-export.sh

# Run the self test.
echo "Running self test on $K8S_VARIANT..."
kubectl exec ${K8S_POD_NAME} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
kubectl cp ./remote-scripts/run-self-test.sh ${K8S_POD_NAME}:/tmp/test/run-self-test.sh
kubectl cp ./remote-scripts/test.py ${K8S_POD_NAME}:/tmp/test/test.py
kubectl cp ./secrets-export.sh ${K8S_POD_NAME}:/tmp/test/secrets-export.sh
kubectl exec ${K8S_POD_NAME} -- /tmp/test/run-self-test.sh
echo "Running self test on $K8S_VARIANT... done."

popd
