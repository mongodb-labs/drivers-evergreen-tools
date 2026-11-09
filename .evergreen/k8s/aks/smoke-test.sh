#!/usr/bin/env bash
# Runs setup-cluster.sh with VERIFY_MONGODB_TAGS=1 against a throwaway
# cluster (~10 min), prints the node resource group's billable resources
# with their tags, then deletes the resource group. Needs vault, az, jq, kubectl.

set -eu

SCRIPT_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
SCRATCH=$(mktemp -d)

cleanup_done=0
teardown ()
{
  if [ "$cleanup_done" = 1 ]; then return; fi
  cleanup_done=1
  rm -rf "$SCRATCH"
  if [ -z "${SMOKE_GROUP:-}" ]; then
    return
  fi
  echo "smoke-test: deleting resource group $SMOKE_GROUP (~10 min)..."
  az group delete -y --name "$SMOKE_GROUP" ||
    echo "smoke-test: WARNING: resource group deletion failed; remove $SMOKE_GROUP manually" 1>&2
}
trap teardown EXIT

# Harvest vault values into the scratch dir; export -p keeps values quoted.
# The helper writes secrets-export.sh into its cwd; setup-cluster.sh would
# source it and clobber the overrides, so it runs from the scratch dir too.
(
  cd "$SCRATCH"
  set -a
  . "$SCRIPT_DIR/../../secrets_handling/setup-secrets.sh" drivers/aks
  export -p | grep -E '^declare -x (AKS|AZUREKMS|MONGODB)_' > "$SCRATCH/vault.env"
)
set -a
. "$SCRATCH/vault.env"
set +a
: "${AKS_LOCATION:?vault did not provide AKS_LOCATION}"
rm -f "$SCRATCH/secrets-export.sh"

SMOKE_NAME=drivers-aks-smoke-$(date +%m%d%H%M%S)-$RANDOM
# Refuse a taken name: the EXIT trap would delete another run's group.
if az group show --name "$SMOKE_NAME" > /dev/null 2>&1; then
  echo "smoke-test: resource group name $SMOKE_NAME is taken; rerun for a fresh name" 1>&2
  exit 1
fi
SMOKE_GROUP="$SMOKE_NAME"
SMOKE_CLUSTER="$SMOKE_NAME"
export AKS_RESOURCE_GROUP="$SMOKE_GROUP"
export AKS_CLUSTER_NAME="$SMOKE_CLUSTER"
export VERIFY_MONGODB_TAGS=1

echo "smoke-test: creating cluster $SMOKE_CLUSTER in ${AKS_LOCATION} (~10 min)..."
(
  cd "$SCRATCH"
  bash "$SCRIPT_DIR/setup-cluster.sh"
)

echo "smoke-test: billable resources in the AKS node resource group:"
MC_RESOURCE_GROUP=$(az aks show -g "$SMOKE_GROUP" -n "$SMOKE_CLUSTER" --query nodeResourceGroup -otsv)
az resource list --resource-group "$MC_RESOURCE_GROUP" \
  --query '[].{name: name, type: type, tags: tags}' --output table

echo "smoke-test: PASS"
