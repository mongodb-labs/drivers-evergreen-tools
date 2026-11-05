#!/usr/bin/env bash

# Smoke test for setup-cluster.sh's DRIVERS-3712 tagging flow: creates a
# throwaway EKS cluster (~20 min, teardown automatic), runs setup-cluster.sh
# with VERIFY_MONGODB_TAGS=1, then deletes the cluster. Exits non-zero on any
# verification failure. Needs vault access to drivers/eks, plus aws, eksctl,
# jq, and kubectl on PATH.

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

# Harvest vault values into the scratch dir. The helper writes
# secrets-export.sh into its cwd, which setup-cluster.sh would source and
# clobber the overrides with, so setup-cluster.sh also runs from here.
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

SMOKE_NAME=drivers-lt-smoke-$(date +%m%d%H%M%S)-$RANDOM
# The EXIT trap deletes $SMOKE_CLUSTER: refuse to run if the name is taken,
# or the teardown would target another run's cluster.
if aws eks describe-cluster --name "$SMOKE_NAME" --region "${EKS_REGION}" > /dev/null 2>&1; then
  echo "smoke-test: cluster name $SMOKE_NAME is taken; rerun for a fresh name" 1>&2
  exit 1
fi
SMOKE_CLUSTER="$SMOKE_NAME"
# Account-wide: derive from the cluster name so runs cannot collide.
SMOKE_ROLE="$SMOKE_CLUSTER-role"
export EKS_CLUSTER_NAME="$SMOKE_CLUSTER"
export EKS_IAM_ROLE_NAME="$SMOKE_ROLE"
export VERIFY_MONGODB_TAGS=1

echo "smoke-test: creating cluster $SMOKE_CLUSTER in ${EKS_REGION} (~15-25 min)..."
(
  cd "$SCRATCH"
  bash "$SCRIPT_DIR/setup-cluster.sh"
)

echo "smoke-test: launch templates created by this run:"
aws ec2 describe-launch-templates --region "${EKS_REGION}" \
  --filters "Name=tag:eks:cluster-name,Values=$SMOKE_CLUSTER" \
  --query 'LaunchTemplates[].{name:LaunchTemplateName,tags:Tags}' \
  --output table

echo "smoke-test: PASS"
