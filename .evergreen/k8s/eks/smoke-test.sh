#!/usr/bin/env bash

# Smoke test for setup-cluster.sh's DRIVERS-3712 tagging flow. Creates a
# throwaway EKS cluster (~20 min, 2 default nodes — teardown is automatic),
# runs setup-cluster.sh against it with VERIFY_MONGODB_TAGS=1 so the tag
# gate covers the cluster, the iamserviceaccount's role, and both launch
# template families, then tears the cluster down. Exits non-zero on any
# verification failure.
#
# Needs vault access to the drivers/eks secrets, plus aws, eksctl, jq, and
# kubectl on PATH.

set -eu

SCRIPT_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
SCRATCH=$(mktemp -d)

cleanup_done=0
teardown ()
{
  if [ "$cleanup_done" = 1 ]; then return; fi
  cleanup_done=1
  rm -rf "$SCRATCH"
  if [ -z "${SMOKE_CLUSTER:-}" ]; then
    return
  fi
  echo "smoke-test: deleting cluster $SMOKE_CLUSTER (~10-15 min)..."
  yes | eksctl delete cluster --name "$SMOKE_CLUSTER" --region "${EKS_REGION}" --wait ||
    echo "smoke-test: WARNING: cluster deletion failed; remove $SMOKE_CLUSTER manually" 1>&2
  if aws iam get-role --role-name "$SMOKE_ROLE" > /dev/null 2>&1; then
    echo "smoke-test: WARNING: role $SMOKE_ROLE still exists; delete it manually" 1>&2
  fi
}
trap teardown EXIT

# Harvest the vault values into the scratch dir: the policy ARN and service
# account name carry over to the throwaway cluster; the vault's cluster name
# and role must not. The helper writes secrets-export.sh into its cwd, which
# setup-cluster.sh would otherwise source and let clobber the overrides — so
# setup-cluster.sh runs from the scratch dir, where that file is removed.
(
  cd "$SCRATCH"
  set -a
  . "$SCRIPT_DIR/../../secrets_handling/setup-secrets.sh" drivers/eks
  env | grep '^EKS_' > "$SCRATCH/vault.env"
)
set -a
. "$SCRATCH/vault.env"
set +a
: "${EKS_POLICY_ARN:?vault did not provide EKS_POLICY_ARN}"
rm -f "$SCRATCH/secrets-export.sh"

SMOKE_CLUSTER=drivers-lt-smoke-$(date +%H%M%S)
SMOKE_ROLE=drivers-lt-smoke-role
export EKS_CLUSTER_NAME="$SMOKE_CLUSTER"
export EKS_IAM_ROLE_NAME="$SMOKE_ROLE"
export VERIFY_MONGODB_TAGS=1

echo "smoke-test: creating cluster $SMOKE_CLUSTER in ${EKS_REGION} (~15-25 min)..."
(
  cd "$SCRATCH"
  bash "$SCRIPT_DIR/setup-cluster.sh"
)

# The gate inside setup-cluster.sh verified the cluster, the role, and both
# launch template families; restate the fresh templates for the record.
echo "smoke-test: launch templates created by this run:"
aws ec2 describe-launch-templates --region "${EKS_REGION}" \
  --filters "Name=tag:eks:cluster-name,Values=$SMOKE_CLUSTER" \
  --query 'LaunchTemplates[].{name:LaunchTemplateName,tags:Tags}' \
  --output table

echo "smoke-test: PASS"
