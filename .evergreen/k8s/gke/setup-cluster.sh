#!/usr/bin/env bash

set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${GKE_PROJECT:-}" ]; then
    . $DRIVERS_TOOLS/.evergreen/secrets_handling/setup-secrets.sh drivers/gke
fi

set -x
bash $DRIVERS_TOOLS/.evergreen/ensure-binary.sh gcloud
gcloud auth login

gcloud beta container --project "$GKE_PROJECT" clusters create-auto "$GKE_CLUSTER_NAME" \
  --region "$GKE_REGION" --release-channel "regular" \
  --network "projects/$GKE_PROJECT/global/networks/default" \
  --subnetwork "projects/$GKE_PROJECT/regions/$GKE_REGION/subnetworks/default" \
  --binauthz-evaluation-mode=DISABLED \
  --service-account=$GKE_SERVICE_ACCOUNT --fleet-project=$GKE_PROJECT

PROJECT_NUMBER="$(gcloud projects describe ${GKE_PROJECT} --format='get(projectNumber)')"
gcloud projects add-iam-policy-binding ${PROJECT_NUMBER} \
    --member=serviceAccount:$GKE_SERVICE_ACCOUNT \
    --role=roles/container.developer
