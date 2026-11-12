#!/usr/bin/env bash
#
# Group-teardown backstop: retries the pod deletion for every variant, not
# just the last stage's. Covers stages whose trap never fired or whose
# in-stage deletion failed. Each stage writes its own kubeconfig, so every
# stage stays retryable here after later stages run.
#
# 20s per variant keeps all three inside the group step's 60s wrapper (the
# trap already gave each pod a 60s-bounded window); a failing variant only
# logs a warning, so the variants after it still run.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

for VARIANT in eks gke aks; do
  VARIANT_DIR=$DRIVERS_TOOLS/.evergreen/k8s/$VARIANT
  if [ ! -d "$VARIANT_DIR" ]; then
    continue
  fi
  # No kubeconfig means setup never fetched credentials, so no pod exists.
  if [ ! -f "$VARIANT_DIR/kubeconfig" ]; then
    echo "Skipping $VARIANT pod teardown: no kubeconfig (setup never reached the credential fetch)."
    continue
  fi
  # A kubeconfig can exist without a secrets file (environment-supplied
  # credentials, or a failure between the credential fetch and the pod
  # record); skip rather than abort the variants after it.
  if [ ! -f "$VARIANT_DIR/secrets-export.sh" ]; then
    echo "Skipping $VARIANT pod teardown: no secrets file (no pod was recorded)."
    continue
  fi
  # Name the pod in the warning even when timeout kills kubectl first; unset
  # it per variant so a variant without secrets cannot inherit the last one's.
  unset K8S_POD_NAME
  # shellcheck source=/dev/null
  . "$VARIANT_DIR/secrets-export.sh"
  if ! KUBECONFIG="$VARIANT_DIR/kubeconfig" timeout 20 bash "$VARIANT_DIR/teardown.sh"; then
    echo "WARNING: ${VARIANT} pod teardown failed; pod ${K8S_POD_NAME:-unknown} may need manual cleanup"
  fi
done
