#!/usr/bin/env bash

set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f $SCRIPT_DIR/secrets-export.sh ]; then
  echo "Sourcing secrets"
  source $SCRIPT_DIR/secrets-export.sh
fi

bash $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
bash $DRIVERS_TOOLS/.evergreen/ensure-binary.sh gcloud

export GCPKMS_KEYFILE_CONTENT=$GKE_KEYFILE_CONTENT
bash $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/login.sh
gcloud container clusters get-credentials  --region $GKE_REGION --project $GKE_PROJECT
kubectl delete pod ${K8S_POD_NAME}
