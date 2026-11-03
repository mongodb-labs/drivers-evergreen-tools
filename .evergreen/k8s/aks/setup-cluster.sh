#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${AZUREKMS_TENANTID:-}" ]; then
    . ./../../secrets_handling/setup-secrets.sh drivers/aks
fi

az logout || true
az login

# Tag all created resources per the MongoDB Cloud Tag Policy (DRIVERS-3712).
MONGODB_OWNER_TAG="${MONGODB_OWNER_TAG:-client-libraries-managers@mongodb.com}"
MONGODB_ENV_TAG="${MONGODB_ENV_TAG:-dev}"

EXISTING=$(az group list | grep "${AKS_RESOURCE_GROUP}" || true)
if [ -n "${EXISTING}" ]; then
  echo "${AKS_RESOURCE_GROUP} already exists!"
  exit 1
fi
AKS_SUBSCRIPTION="$(az account show --query id --output tsv)"
az group create --name "${AKS_RESOURCE_GROUP}" --location ${AKS_LOCATION} \
  --tags "mongodb-owner=${MONGODB_OWNER_TAG}" "mongodb-env=${MONGODB_ENV_TAG}"
az aks create -g "${AKS_RESOURCE_GROUP}" -n "${AKS_CLUSTER_NAME}" \
  --node-count 1 --enable-oidc-issuer --enable-workload-identity \
  --enable-cluster-autoscaler --min-count 1 --max-count 3 \
  --generate-ssh-keys \
  --tags "mongodb-owner=${MONGODB_OWNER_TAG}" "mongodb-env=${MONGODB_ENV_TAG}"
AKS_OIDC_ISSUER="$(az aks show -n "${AKS_CLUSTER_NAME}" -g "${AKS_RESOURCE_GROUP}" --query "oidcIssuerProfile.issuerUrl" -otsv)"
export AKS_OIDC_ISSUER
az account set --subscription "${AKS_SUBSCRIPTION}"
az identity create --name "${AKS_USER_ASSIGNED_IDENTITY_NAME}" --resource-group "${AKS_RESOURCE_GROUP}" \
  --location "${AKS_LOCATION}" --subscription "${AKS_SUBSCRIPTION}" \
  --tags "mongodb-owner=${MONGODB_OWNER_TAG}" "mongodb-env=${MONGODB_ENV_TAG}"
USER_ASSIGNED_CLIENT_ID="$(az identity show --resource-group "${AKS_RESOURCE_GROUP}" \
  --name "${AKS_USER_ASSIGNED_IDENTITY_NAME}" --query 'clientId' -otsv)"
export USER_ASSIGNED_CLIENT_ID
az aks get-credentials --overwrite-existing -n "${AKS_CLUSTER_NAME}" -g "${AKS_RESOURCE_GROUP}"
. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: ${USER_ASSIGNED_CLIENT_ID}
  name: ${AKS_SERVICE_ACCOUNT_NAME}
  namespace: ${AKS_SERVICE_ACCOUNT_NAMESPACE}
EOF
az identity federated-credential create --name ${AKS_FEDERATED_IDENTITY_CREDENTIAL_NAME} \
  --identity-name ${AKS_USER_ASSIGNED_IDENTITY_NAME} --resource-group ${AKS_RESOURCE_GROUP} \
  --issuer ${AKS_OIDC_ISSUER} --subject system:serviceaccount:${AKS_SERVICE_ACCOUNT_NAMESPACE}:${AKS_SERVICE_ACCOUNT_NAME}
# Assign the resource group
RESOURCE_SUBSCRIPTION=$(az group show --resource-group $AKS_RESOURCE_GROUP -o tsv --query id)
export RESOURCE_SUBSCRIPTION
az role assignment create --role "Azure Kubernetes Service RBAC Admin" --assignee $AKS_APPLICATION_ID  --scope $RESOURCE_SUBSCRIPTION

# Verify the created resources' tags when requested (DRIVERS-3712).
if [ -n "${VERIFY_MONGODB_TAGS:-}" ]; then
  . "$DRIVERS_TOOLS"/.evergreen/verify-tags.sh
  verify_cloud_tags "AKS resource group ${AKS_RESOURCE_GROUP}" \
    "$(az group show --name "${AKS_RESOURCE_GROUP}" --query tags --output json)"
  verify_cloud_tags "AKS cluster ${AKS_CLUSTER_NAME}" \
    "$(az aks show --name "${AKS_CLUSTER_NAME}" --resource-group "${AKS_RESOURCE_GROUP}" --query tags --output json)"
  verify_cloud_tags "AKS identity ${AKS_USER_ASSIGNED_IDENTITY_NAME}" \
    "$(az identity show --name "${AKS_USER_ASSIGNED_IDENTITY_NAME}" --resource-group "${AKS_RESOURCE_GROUP}" --query tags --output json)"
fi
