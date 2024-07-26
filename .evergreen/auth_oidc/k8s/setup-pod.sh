#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Set the current K8S_VARIANT.
K8S_VARIANT=${K8S_VARIANT:-$1}
echo "export K8S_VARIANT=$K8S_VARIANT" >> secrets-export.sh
VARIANT=$(echo "$K8S_VARIANT" | tr '[:upper:]' '[:lower:]')
VARIANT_DIR=$DRIVERS_TOOLS/.evergreen/k8s/$VARIANT
echo "export K8S_VARIANT_DIR=$VARIANT_DIR" >> secrets-export.sh

# Set up the pod.
echo "Setting up $VARIANT pod..."
. $VARIANT_DIR/setup.sh
echo "Setting up $VARIANT pod... done."

popd
