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
  # Resolve starter templates through the cluster's node groups and match
  # each by exact name: a name-prefix filter would also match starters of
  # clusters whose names share the prefix, and tagging would overwrite their
  # ownership tags. EKS's generated copies carry the eks:cluster-name tag.
  # Every response is checked before parsing, so a failed call aborts.
  local ids="" resp resp_ids ng
  resp=$(aws eks list-nodegroups --cluster-name "${EKS_CLUSTER_NAME}" \
    --region "${EKS_REGION}" --output json) || {
    echo "verify-eks-setup: list-nodegroups failed" 1>&2
    return 1
  }
  resp_ids=$(echo "$resp" | jq -r '.nodegroups[]') || {
    echo "verify-eks-setup: parsing list-nodegroups output failed" 1>&2
    return 1
  }
  # shellcheck disable=SC2046,SC2086  # names are newline-separated; no spaces or globs
  for ng in $resp_ids; do
    resp=$(aws ec2 describe-launch-templates --region "${EKS_REGION}" \
      --filters "Name=launch-template-name,Values=eksctl-${EKS_CLUSTER_NAME}-nodegroup-${ng}" \
      --output json) || {
      echo "verify-eks-setup: describe-launch-templates (${ng}) failed" 1>&2
      return 1
    }
    resp_ids=$(echo "$resp" | jq -r '.LaunchTemplates[].LaunchTemplateId') || {
      echo "verify-eks-setup: parsing describe-launch-templates output failed" 1>&2
      return 1
    }
    ids="$ids $resp_ids"
  done
  resp=$(aws ec2 describe-launch-templates --region "${EKS_REGION}" \
    --filters "Name=tag:eks:cluster-name,Values=${EKS_CLUSTER_NAME}" \
    --output json) || {
    echo "verify-eks-setup: describe-launch-templates (generated) failed" 1>&2
    return 1
  }
  resp_ids=$(echo "$resp" | jq -r '.LaunchTemplates[].LaunchTemplateId') || {
    echo "verify-eks-setup: parsing describe-launch-templates output failed" 1>&2
    return 1
  }
  ids="$ids $resp_ids"
  echo "$ids" | tr ' \t' '\n\n' | sed '/^$/d' | sort -u
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
  LT_IDS=$(launch_template_ids)
  # shellcheck disable=SC2046,SC2086  # ids are newline-separated; no spaces or globs
  for LT_ID in ${LT_IDS}; do
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
    . "$SCRIPT_DIR"/../../secrets_handling/setup-secrets.sh drivers/eks
  fi

  verify_eks_tags
fi
