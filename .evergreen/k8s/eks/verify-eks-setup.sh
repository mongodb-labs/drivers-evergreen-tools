#!/usr/bin/env bash

# Tag verification for the drivers EKS setup: the cluster, the iamserviceaccount's
# role, and every node group launch template. Sourced by setup-cluster.sh, and
# runnable standalone against an existing cluster; exits non-zero naming the
# first resource lacking mongodb-owner/mongodb-env.

set -eu

# Own directory, so verify-tags.sh resolves from this checkout rather than the ambient DRIVERS_TOOLS.
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})

launch_template_ids ()
{
  # eksctl's starter templates (eksctl-<cluster>-nodegroup-*) and EKS's
  # generated copies (tagged eks:cluster-name): two describes, because EC2
  # ANDs filters within a call.
  {
    aws ec2 describe-launch-templates --region "${EKS_REGION}" \
      --filters "Name=launch-template-name,Values=eksctl-${EKS_CLUSTER_NAME}-nodegroup-*" \
      --output json | jq -r '.LaunchTemplates[].LaunchTemplateId'
    aws ec2 describe-launch-templates --region "${EKS_REGION}" \
      --filters "Name=tag:eks:cluster-name,Values=${EKS_CLUSTER_NAME}" \
      --output json | jq -r '.LaunchTemplates[].LaunchTemplateId'
  } | sort -u
}

verify_eks_tags ()
{
  . "$SCRIPT_DIR"/../../verify-tags.sh

  # Read first, reshape second: a pipeline would mask the aws error as "lacks tags".
  CLUSTER_TAGS=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" \
    --region "${EKS_REGION}" --query "cluster.tags" --output json)
  verify_cloud_tags "EKS cluster ${EKS_CLUSTER_NAME}" "${CLUSTER_TAGS}"

  ROLE_TAGS_RAW=$(aws iam get-role --role-name "${EKS_IAM_ROLE_NAME}" \
    --query "Role.Tags" --output json)
  # get-role returns {Key, Value} objects; convert to a map for the helper.
  ROLE_TAGS=$(echo "${ROLE_TAGS_RAW}" | jq 'map({(.Key): .Value}) | add')
  verify_cloud_tags "EKS IAM role ${EKS_IAM_ROLE_NAME}" "${ROLE_TAGS}"

  # setup-cluster.sh tags both families right after cluster creation; this
  # re-checks they all still carry the policy.
  # shellcheck disable=SC2046,SC2086  # ids are newline-separated; no spaces or globs
  for LT_ID in $(launch_template_ids); do
    LT_TAGS_RAW=$(aws ec2 describe-launch-templates --region "${EKS_REGION}" \
      --launch-template-ids "${LT_ID}" --query "LaunchTemplates[0].Tags" \
      --output json)
    # describe returns {Key, Value} objects; convert to a map for the helper.
    LT_TAGS=$(echo "${LT_TAGS_RAW}" | jq 'map({(.Key): .Value}) | add')
    verify_cloud_tags "EKS launch template ${LT_ID}" "${LT_TAGS}"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . $SCRIPT_DIR/../../handle-paths.sh

  if [ -f ./secrets-export.sh ]; then
    source ./secrets-export.sh
  fi
  if [ -z "${EKS_CLUSTER_NAME:-}" ]; then
    . ./../../secrets_handling/setup-secrets.sh drivers/eks
  fi

  verify_eks_tags
fi
