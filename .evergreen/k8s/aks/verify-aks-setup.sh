#!/usr/bin/env bash

# Tag verification for the drivers AKS setup: the resource group, the
# cluster, its node resource group, every node pool, and the identity.
# Exits non-zero naming the first resource lacking mongodb-owner/mongodb-env.

set -eu

# Own directory, so verify-tags.sh resolves from this checkout rather than the ambient DRIVERS_TOOLS.
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})

verify_aks_tags ()
{
  . "$SCRIPT_DIR"/../../verify-tags.sh

  # az group create tags the parent resource group in setup-cluster.sh.
  GROUP_TAGS=$(az group show --name "${AKS_RESOURCE_GROUP}" --query tags --output json)
  verify_cloud_tags "AKS resource group ${AKS_RESOURCE_GROUP}" "${GROUP_TAGS}"

  CLUSTER_TAGS=$(az aks show --name "${AKS_CLUSTER_NAME}" \
    --resource-group "${AKS_RESOURCE_GROUP}" --query tags --output json)
  verify_cloud_tags "AKS cluster ${AKS_CLUSTER_NAME}" "${CLUSTER_TAGS}"

  # az aks create --tags reaches only the cluster resource: the AKS-created
  # node resource group and node pools hold the billable resources.
  MC_RESOURCE_GROUP=$(az aks show --name "${AKS_CLUSTER_NAME}" \
    --resource-group "${AKS_RESOURCE_GROUP}" --query nodeResourceGroup --output tsv)
  MC_TAGS=$(az group show --name "${MC_RESOURCE_GROUP}" --query tags --output json)
  verify_cloud_tags "AKS node resource group ${MC_RESOURCE_GROUP}" "${MC_TAGS}"

  POOLS_JSON=$(az aks nodepool list --resource-group "${AKS_RESOURCE_GROUP}" \
    --cluster-name "${AKS_CLUSTER_NAME}" --output json)
  # Checked assignment: a for-word jq failure does not trip set -e.
  AKS_POOL_NAMES=$(echo "${POOLS_JSON}" | jq -r '.[].name')
  for AKS_POOL in ${AKS_POOL_NAMES}; do
    POOL_TAGS=$(echo "${POOLS_JSON}" | jq -r --arg pool "${AKS_POOL}" \
      '.[] | select(.name == $pool) | .tags')
    verify_cloud_tags "AKS node pool ${AKS_POOL}" "${POOL_TAGS}"
  done

  # The identity check cannot be skipped: the caller must name the identity.
  IDENTITY_TAGS=$(az identity show \
    --name "${AKS_USER_ASSIGNED_IDENTITY_NAME:?must name the workload identity to verify}" \
    --resource-group "${AKS_RESOURCE_GROUP}" --query tags --output json)
  verify_cloud_tags "AKS identity ${AKS_USER_ASSIGNED_IDENTITY_NAME}" "${IDENTITY_TAGS}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . $SCRIPT_DIR/../../handle-paths.sh

  # ./secrets-export.sh and the vault are fallbacks, not overrides.
  if [ -z "${AKS_CLUSTER_NAME:-}" ] || [ -z "${AKS_RESOURCE_GROUP:-}" ]; then
    if [ -f ./secrets-export.sh ]; then
      source ./secrets-export.sh
    fi
    if [ -z "${AKS_CLUSTER_NAME:-}" ] || [ -z "${AKS_RESOURCE_GROUP:-}" ]; then
      . "$SCRIPT_DIR"/../../secrets_handling/setup-secrets.sh drivers/aks
    fi
  fi

  verify_aks_tags
fi
