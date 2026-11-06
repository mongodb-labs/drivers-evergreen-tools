#!/usr/bin/env bash

# Tag verification for the drivers AKS setup: the cluster, the AKS-created
# node resource group, every node pool, and the user-assigned identity.
# Sourced by setup-cluster.sh and setup.sh, and runnable standalone against
# an existing cluster; exits non-zero naming the first resource lacking
# mongodb-owner/mongodb-env.

set -eu

# Own directory, so verify-tags.sh resolves from this checkout rather than the ambient DRIVERS_TOOLS.
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})

verify_aks_tags ()
{
  . "$SCRIPT_DIR"/../../verify-tags.sh

  CLUSTER_TAGS=$(az aks show --name "${AKS_CLUSTER_NAME}" \
    --resource-group "${AKS_RESOURCE_GROUP}" --query tags --output json)
  verify_cloud_tags "AKS cluster ${AKS_CLUSTER_NAME}" "${CLUSTER_TAGS}"

  # az aks create --tags reaches only the cluster resource. The node
  # resource group is created by AKS and holds the billable nodes, the load
  # balancer IP, and the networks; the node pools back the billable VMSS.
  MC_RESOURCE_GROUP=$(az aks show --name "${AKS_CLUSTER_NAME}" \
    --resource-group "${AKS_RESOURCE_GROUP}" --query nodeResourceGroup --output tsv)
  MC_TAGS=$(az group show --name "${MC_RESOURCE_GROUP}" --query tags --output json)
  verify_cloud_tags "AKS node resource group ${MC_RESOURCE_GROUP}" "${MC_TAGS}"

  POOLS_JSON=$(az aks nodepool list --resource-group "${AKS_RESOURCE_GROUP}" \
    --cluster-name "${AKS_CLUSTER_NAME}" --output json)
  for AKS_POOL in $(echo "${POOLS_JSON}" | jq -r '.[].name'); do
    POOL_TAGS=$(echo "${POOLS_JSON}" | jq -r --arg pool "${AKS_POOL}" \
      '.[] | select(.name == $pool) | .tags')
    verify_cloud_tags "AKS node pool ${AKS_POOL}" "${POOL_TAGS}"
  done

  # The pod flow runs on the pre-provisioned cluster, whose identity the
  # vault does not name for every caller.
  if [ -n "${AKS_USER_ASSIGNED_IDENTITY_NAME:-}" ]; then
    IDENTITY_TAGS=$(az identity show --name "${AKS_USER_ASSIGNED_IDENTITY_NAME}" \
      --resource-group "${AKS_RESOURCE_GROUP}" --query tags --output json)
    verify_cloud_tags "AKS identity ${AKS_USER_ASSIGNED_IDENTITY_NAME}" "${IDENTITY_TAGS}"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . $SCRIPT_DIR/../../handle-paths.sh

  if [ -f ./secrets-export.sh ]; then
    source ./secrets-export.sh
  fi
  if [ -z "${AZUREKMS_TENANTID:-}" ]; then
    . "$SCRIPT_DIR"/../../secrets_handling/setup-secrets.sh drivers/aks
  fi

  verify_aks_tags
fi
