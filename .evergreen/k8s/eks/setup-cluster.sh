#!/usr/bin/env bash

set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${EKS_CLUSTER_NAME:-}" ]; then
    . ./../../secrets_handling/setup-secrets.sh drivers/eks
fi

eksctl create cluster --name $EKS_CLUSTER_NAME --zones "${EKS_REGION}a,${EKS_REGION}b"
kubectl config set-context --current
eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER_NAME --approve
eksctl create iamserviceaccount \
    --name $EKS_SERVICE_ACCOUNT_NAME \
    --cluster $EKS_CLUSTER_NAME \
    --role-name $EKS_IAM_ROLE_NAME \
    --attach-policy-arn $EKS_POLICY_ARN \
    --approve \
    --override-existing-serviceaccounts
