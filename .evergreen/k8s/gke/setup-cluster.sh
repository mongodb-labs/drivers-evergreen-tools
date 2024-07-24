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

gcloud container clusters create "$GKE_CLUSTER_NAME" \
    --zone ${GKE_LOCATION} \
    --node-locations ${GKE_LOCATION} \
    --disk-type pd-standard \
    --enable-fleet \
    --workload-pool=${GKE_PROJECT}.svc.id.goog \
    --network "projects/$GKE_PROJECT/global/networks/default" \
    --subnetwork "projects/$GKE_PROJECT/regions/$GKE_REGION/subnetworks/default" \
    --binauthz-evaluation-mode=DISABLED \
    --service-account=$GKE_SERVICE_ACCOUNT

PROJECT_NUMBER="$(gcloud projects describe ${GKE_PROJECT} --format='get(projectNumber)')"
gcloud projects add-iam-policy-binding ${PROJECT_NUMBER} \
    --member=serviceAccount:$GKE_SERVICE_ACCOUNT \
    --role=roles/container.developer
