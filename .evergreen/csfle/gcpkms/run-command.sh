#!/usr/bin/env bash
# Run a command on a remote GCE instance.
set -o errexit # Exit on first command error.
if [ -z "$GCPKMS_GCLOUD" ] || [ -z "$GCPKMS_PROJECT" ] || [ -z "$GCPKMS_ZONE" ] || [ -z "$GCPKMS_INSTANCENAME" ] || [ -z "$GCPKMS_CMD" ]; then
    echo "Please set the following required environment variables"
    echo " GCPKMS_GCLOUD to the path of the gcloud binary"
    echo " GCPKMS_PROJECT to the GCP project"
    echo " GCPKMS_ZONE to the GCP zone"
    echo " GCPKMS_INSTANCENAME to the GCE instance name"
    echo " GCPKMS_CMD to a command to run on GCE instance"
    exit 1
fi

echo "Running '$GCPKMS_CMD' on GCE instance ... begin"
$GCPKMS_GCLOUD compute ssh "$GCPKMS_INSTANCENAME" \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --command "$GCPKMS_CMD"
echo "Running '$GCPKMS_CMD' on GCE instance ... end"
