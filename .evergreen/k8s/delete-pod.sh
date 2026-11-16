#!/usr/bin/env bash
#
# Shared pod deletion for the k8s variant teardowns. The caller passes the
# provider name (for the skip message) and the namespace setup.sh created the
# pod in; K8S_POD_NAME comes from the variant's recorded state.
#
# The namespace must be explicit: --ignore-not-found would otherwise turn a
# wrong-namespace lookup into reported success while the pod keeps running.
set -eu

PROVIDER=${1:?provider name is required}

# Skip before validating the namespace: a setup that failed before fetching
# vault secrets recorded neither the pod nor the namespace, and the missing
# namespace must not turn the skip into a failure.
if [ -z "${K8S_POD_NAME:-}" ]; then
  echo "Skipping $PROVIDER pod teardown: no pod was created (K8S_POD_NAME is not set)."
  exit 0
fi

NAMESPACE=${2:?pod namespace is required}

kubectl delete pod "${K8S_POD_NAME}" --namespace "$NAMESPACE" --ignore-not-found --timeout=60s
