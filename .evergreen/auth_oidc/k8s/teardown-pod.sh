#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Source the secrets if setup wrote them; it may have failed before doing so.
if [ -f secrets-export.sh ]; then
  source secrets-export.sh
fi

# If the variant was never recorded, setup-pod.sh never ran and there is no
# pod to tear down.
if [ -z "${K8S_VARIANT_DIR:-}" ]; then
  echo "Skipping pod teardown: setup-pod.sh did not complete (K8S_VARIANT_DIR is not set)."
  popd
  exit 0
fi

# Tear down the pod.
echo "Tearing down $K8S_VARIANT pod..."
. $K8S_VARIANT_DIR/teardown.sh
echo "Tearing down $K8S_VARIANT pod... done."

popd
