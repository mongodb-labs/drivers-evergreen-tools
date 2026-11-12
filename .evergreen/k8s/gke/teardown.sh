#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f $SCRIPT_DIR/secrets-export.sh ]; then
  echo "Sourcing secrets"
  source $SCRIPT_DIR/secrets-export.sh
fi

if [ -z "${K8S_POD_NAME:-}" ]; then
  echo "Skipping gke pod teardown: no pod was created (K8S_POD_NAME is not set)."
else
  kubectl delete pod ${K8S_POD_NAME} --ignore-not-found
fi
