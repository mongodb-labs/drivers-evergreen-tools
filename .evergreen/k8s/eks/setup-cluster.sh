#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${EKS_CLUSTER_NAME:-}" ]; then
    . ./../../secrets_handling/setup-secrets.sh drivers/eks
fi

# Tag the cluster and the iamserviceaccount's role.
MONGODB_OWNER_TAG="${MONGODB_OWNER_TAG:-client-libraries-managers@mongodb.com}"
MONGODB_ENV_TAG="${MONGODB_ENV_TAG:-dev}"

# --region must be explicit: eksctl otherwise falls back to the ambient
# AWS region (profile/env default), which may differ from ${EKS_REGION}a/b
# zone names — leaving the cluster in the wrong region.
eksctl create cluster --name $EKS_CLUSTER_NAME --region "${EKS_REGION}" --zones "${EKS_REGION}a,${EKS_REGION}b" \
  --tags "mongodb-owner=${MONGODB_OWNER_TAG},mongodb-env=${MONGODB_ENV_TAG}"
kubectl config set-context --current
eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER_NAME --region "${EKS_REGION}" --approve
eksctl create iamserviceaccount \
    --name $EKS_SERVICE_ACCOUNT_NAME \
    --cluster $EKS_CLUSTER_NAME \
    --region "${EKS_REGION}" \
    --role-name $EKS_IAM_ROLE_NAME \
    --attach-policy-arn $EKS_POLICY_ARN \
    --tags "mongodb-owner=${MONGODB_OWNER_TAG},mongodb-env=${MONGODB_ENV_TAG}" \
    --approve \
    --override-existing-serviceaccounts

# eksctl's --tags reaches the stack, not the role.
aws iam tag-role --role-name "$EKS_IAM_ROLE_NAME" --tags \
  "Key=mongodb-owner,Value=${MONGODB_OWNER_TAG}" \
  "Key=mongodb-env,Value=${MONGODB_ENV_TAG}"

# The cluster's --tags does not reach the launch templates: eksctl creates
# its starter untagged, and EKS stamps its generated copy with service tags only.
. "$SCRIPT_DIR"/verify-eks-setup.sh
LT_IDS=$(launch_template_ids)
if [ -n "${LT_IDS//[[:space:]]/}" ]; then
  # shellcheck disable=SC2086  # ids are newline-separated; no spaces or globs
  aws ec2 create-tags --region "${EKS_REGION}" --resources ${LT_IDS} \
    --tags "Key=mongodb-owner,Value=${MONGODB_OWNER_TAG}" \
           "Key=mongodb-env,Value=${MONGODB_ENV_TAG}"
fi

# Verify the cluster's, role's, and launch templates' tags when requested.
if [ -n "${VERIFY_MONGODB_TAGS:-}" ]; then
  verify_eks_tags
fi
