# AKS Cluster Management

Scripts to manage a drivers test cluster on Azure.

## Cluster Management

These steps must be done by an account with admin access (one time):

1. Create an App Registration
2. Store the secrets in the AWS vault
3. Run `setup-cluster.sh`

`setup-cluster.sh` tags all resources it creates with
`mongodb-owner=client-libraries-managers@mongodb.com`, `mongodb-env=dev`.
Override with `MONGODB_OWNER_TAG`/`MONGODB_ENV_TAG`. Set `VERIFY_MONGODB_TAGS=1`
to verify after creation.

`az aks create --tags` reaches only the cluster resource: setup-cluster.sh
also tags the AKS-created `MC_*` node resource group (which holds the
billable nodes, the load balancer IP, and the networks) and each node pool
(which backs the billable VMSS). If a provisioning step fails, the partially
created resource group is deleted so a re-run starts clean.

## Tag Verification

Run `verify-aks-setup.sh` against an existing cluster — exporting
`AKS_CLUSTER_NAME`, `AKS_RESOURCE_GROUP`, and `AKS_USER_ASSIGNED_IDENTITY_NAME`,
or with none of them set so it reads the aks vault — to re-check that the
cluster, its node resource group, every node pool, and the identity still
carry the policy tags. It exits non-zero naming the first resource found
lacking them.

The pod flow (`setup.sh`) runs the same verification when
`VERIFY_MONGODB_TAGS=1`.

For a cluster created before the node resource group and node pools were
tagged, run this once:

```bash
MC_RESOURCE_GROUP="$(az aks show -g "${AKS_RESOURCE_GROUP}" -n "${AKS_CLUSTER_NAME}" --query nodeResourceGroup -otsv)"
az tag create --resource-id "$(az group show -n "${MC_RESOURCE_GROUP}" --query id -otsv)" \
  --tags "mongodb-owner=client-libraries-managers@mongodb.com" "mongodb-env=dev"
az aks nodepool list -g "${AKS_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER_NAME}" --query '[].name' -otsv |
  while read -r pool; do
    az aks nodepool update -g "${AKS_RESOURCE_GROUP}" --cluster-name "${AKS_CLUSTER_NAME}" \
      -n "$pool" --tags "mongodb-owner=client-libraries-managers@mongodb.com" "mongodb-env=dev"
  done
```

## Smoke Test

`smoke-test.sh` runs `setup-cluster.sh` end to end against a throwaway
cluster (~10 minutes): it creates a uniquely named resource group and
cluster, verifies the tags, prints the node resource group's billable
resources with their tags, and deletes the resource group. It needs vault
access to `drivers/aks` and is not run in CI.

## Usage

These steps can be run using the drivers test secrets role:

1. Run `setup.sh`
2. Run the desired tests in the pod.
3. Run `teardown.sh`
