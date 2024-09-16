#!/usr/bin/env bash
# Delete GCE instance.
set -o errexit # Exit on first command error.

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f $SCRIPT_DIR/secrets-export.sh ]; then
  echo "Sourcing secrets"
  source $SCRIPT_DIR/secrets-export.sh
fi

if [ -z "$GCPKMS_GCLOUD" ] || [ -z "$GCPKMS_PROJECT" ] || [ -z "$GCPKMS_ZONE" ] || [ -z "$GCPKMS_INSTANCENAME" ]; then
    echo "Please set the following required environment variables"
    echo " GCPKMS_GCLOUD to the path of the gcloud binary"
    echo " GCPKMS_PROJECT to the GCP project"
    echo " GCPKMS_ZONE to the GCP zone"
    echo " GCPKMS_INSTANCENAME to the GCE instance name"
    exit 1
fi

echo "Deleting GCE instance ($GCPKMS_INSTANCENAME) ... begin"
$GCPKMS_GCLOUD --quiet compute instances delete $GCPKMS_INSTANCENAME \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT
echo "Deleting GCE instance ($GCPKMS_INSTANCENAME) ... end"

echo "Removing SSH key ... begin"
$GCPKMS_GCLOUD compute os-login ssh-keys remove --key-file ~/.ssh/google_compute_engine.pub
echo "Removing SSH key ... end"
