#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

# If setup.sh failed before writing secrets, no Atlas deployment was created
# either (setup.sh fetches secrets before creating the deployment).
if [ ! -f $SCRIPT_DIR/secrets-export.sh ]; then
  echo "Skipping Atlas teardown: setup.sh did not write secrets-export.sh; nothing was created."
  exit 0
fi
source $SCRIPT_DIR/secrets-export.sh

# If running locally, just exit
if [ "${OIDC_SERVER_TYPE:-}" == "local" ]; then
  exit 0
fi

ATLAS_SECRETS=$DRIVERS_TOOLS/.evergreen/atlas/secrets-export.sh

# setup.sh records CLUSTER_NAME before calling create_deployment; if no name
# was recorded, the deployment was never created. The command substitution
# keeps the secrets out of this shell; `|| true` keeps a malformed file from
# aborting under set -e.
CLUSTER_NAME=""
if [ -f "$ATLAS_SECRETS" ]; then
  # shellcheck disable=SC1090  # the secrets file is a generated artifact
  CLUSTER_NAME=$( . "$ATLAS_SECRETS" && printf '%s' "${CLUSTER_NAME:-}" ) || true
fi
if [ -z "$CLUSTER_NAME" ]; then
  echo "Skipping Atlas teardown: no CLUSTER_NAME recorded; the deployment was never created."
  exit 0
fi

# The Atlas API keys come from the k8s secrets file; without them the
# deployment cannot be deleted here, so name it for manual cleanup: the task
# group's cleanup step deletes DRIVERS_TOOLS, so the state file below will not
# outlive this task.
if [ -z "${OIDC_ATLAS_PUBLIC_API_KEY:-}" ] || [ -z "${OIDC_ATLAS_PRIVATE_API_KEY:-}" ] || [ -z "${OIDC_ATLAS_GROUP_ID:-}" ]; then
  echo "WARNING: Atlas API credentials are missing; deployment $CLUSTER_NAME may need manual cleanup."
  exit 0
fi

# Tear down the Atlas Cluster
export DRIVERS_ATLAS_PUBLIC_API_KEY=$OIDC_ATLAS_PUBLIC_API_KEY
export DRIVERS_ATLAS_PRIVATE_API_KEY=$OIDC_ATLAS_PRIVATE_API_KEY
export DRIVERS_ATLAS_GROUP_ID=$OIDC_ATLAS_GROUP_ID
bash $DRIVERS_TOOLS/.evergreen/atlas/teardown-atlas-cluster.sh
