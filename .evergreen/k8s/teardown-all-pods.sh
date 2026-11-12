#!/usr/bin/env bash
#
# Group-teardown backstop for the auth_oidc k8s pod lifecycle: retries the
# pod deletion for EVERY provider variant, not just the last stage's. The
# per-stage trap in the test functions deletes each pod while its own
# kubeconfig is still current; this backstop covers stages killed before
# their trap fired and stages whose in-stage deletion failed. Each stage
# writes its cloud credentials to its own kubeconfig (the stage body
# exports KUBECONFIG before setup runs), and each variant records its pod
# name in its own secrets-export.sh, so every stage is independently
# retryable here.
#
# Each variant is bounded and tolerated: one stalled or failing variant
# must neither eat the group budget the Atlas teardown after this needs
# nor mask the variants after it. The bound is tighter than the primary
# path's (20s per variant vs the trap's 60s-bounded delete) because this
# is a retry: the trap already gave the pod its full window, and all
# three variants must fit the group step's 60s wrapper.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

for VARIANT in eks gke aks; do
  VARIANT_DIR=$DRIVERS_TOOLS/.evergreen/k8s/$VARIANT
  if [ ! -d "$VARIANT_DIR" ]; then
    continue
  fi
  # A stage whose setup never reached the credential fetch has no
  # kubeconfig and could not have created a pod.
  if [ ! -f "$VARIANT_DIR/kubeconfig" ]; then
    echo "Skipping $VARIANT pod teardown: no kubeconfig (setup never reached the credential fetch)."
    continue
  fi
  # The pod name is recorded per variant; include it in the warning so the
  # identity survives in the uploaded task log even when a timeout kills
  # the delete before kubectl can name the pod itself.
  unset K8S_POD_NAME
  # shellcheck source=/dev/null
  . "$VARIANT_DIR/secrets-export.sh"
  if ! KUBECONFIG="$VARIANT_DIR/kubeconfig" timeout 20 bash "$VARIANT_DIR/teardown.sh"; then
    echo "WARNING: ${VARIANT} pod teardown failed; pod ${K8S_POD_NAME:-unknown} may need manual cleanup"
  fi
done
