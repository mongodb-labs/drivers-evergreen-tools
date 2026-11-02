#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${GKE_PROJECT:-}" ]; then
    . $DRIVERS_TOOLS/.evergreen/secrets_handling/setup-secrets.sh drivers/gke
fi

. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh gcloud
gcloud auth login

# Label all created resources per the MongoDB Cloud Tag Policy (DRIVERS-3712).
# GCP labels are lowercase-only, so the owner default omits @mongodb.com.
MONGODB_OWNER_TAG="${MONGODB_OWNER_TAG:-client-libraries-managers}"
MONGODB_ENV_TAG="${MONGODB_ENV_TAG:-dev}"

gcloud beta container --project "$GKE_PROJECT" clusters create-auto "$GKE_CLUSTER_NAME" \
  --region "$GKE_REGION" --release-channel "regular" \
  --network "projects/$GKE_PROJECT/global/networks/default" \
  --subnetwork "projects/$GKE_PROJECT/regions/$GKE_REGION/subnetworks/default" \
  --binauthz-evaluation-mode=DISABLED \
  --service-account=$GKE_SERVICE_ACCOUNT --fleet-project=$GKE_PROJECT \
  --labels "mongodb-owner=${MONGODB_OWNER_TAG},mongodb-env=${MONGODB_ENV_TAG}"

PROJECT_NUMBER="$(gcloud projects describe ${GKE_PROJECT} --format='get(projectNumber)')"
gcloud projects add-iam-policy-binding ${PROJECT_NUMBER} \
    --member=serviceAccount:$GKE_SERVICE_ACCOUNT \
    --role=roles/container.developer

# Verify the cluster's labels when requested (DRIVERS-3712).
if [ -n "${VERIFY_MONGODB_TAGS:-}" ]; then
  . "$DRIVERS_TOOLS"/.evergreen/verify-tags.sh
  verify_cloud_tags "GKE cluster ${GKE_CLUSTER_NAME}" \
    "$(gcloud container clusters describe "${GKE_CLUSTER_NAME}" --region "${GKE_REGION}" --project "${GKE_PROJECT}" --format "json(resourceLabels)")" "resourceLabels"
fi
