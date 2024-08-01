#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

# Handle secrets from vault.
if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
else
  echo "Missing secrets file."
  exit 1
fi

eksctl delete cluster --name $EKS_CLUSTER_NAME --region $EKS_REGION
