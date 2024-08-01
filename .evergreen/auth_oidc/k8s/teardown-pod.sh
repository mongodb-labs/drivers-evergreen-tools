#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

source secrets-export.sh

# Tear down the pod.
echo "Tearding down $K8S_VARIANT pod..."
. $K8S_VARIANT_DIR/teardown.sh
echo "Tearding down $K8S_VARIANT pod... done."

popd
