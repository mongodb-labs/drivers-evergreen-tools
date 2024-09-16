#!/usr/bin/env bash
# Create a GCE instance.
set -o errexit # Exit on first command error.

VARLIST=(
GCPKMS_GCLOUD
GCPKMS_PROJECT
GCPKMS_ZONE
GCPKMS_SERVICEACCOUNT
GCPKMS_IMAGEPROJECT
GCPKMS_IMAGEFAMILY
GCPKMS_MACHINETYPE
GCPKMS_DISKSIZE
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

GCPKMS_INSTANCENAME="instancename-$RANDOM"

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

# Create GCE instance.
echo "Creating GCE instance ($GCPKMS_INSTANCENAME) ... begin"
echo "Using service account: $GCPKMS_SERVICEACCOUNT"
# Add cloudkms scope for making KMS requests.
# Add compute scope so instance can self-delete.
# enable-oslogin enables SSH keys to be managed from the Google account. SSH keys are deleted in delete-instance.sh. Without enable-oslogin, SSH keys are added to Project Metadata and may hit resource limits.
$GCPKMS_GCLOUD compute instances create $GCPKMS_INSTANCENAME \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --machine-type $GCPKMS_MACHINETYPE \
    --service-account $GCPKMS_SERVICEACCOUNT \
    --image-project $GCPKMS_IMAGEPROJECT \
    --image-family $GCPKMS_IMAGEFAMILY \
    --metadata-from-file=startup-script=$DRIVERS_TOOLS/.evergreen/csfle/gcpkms/remote-scripts/startup.sh \
    --scopes https://www.googleapis.com/auth/cloudkms,https://www.googleapis.com/auth/compute \
    --metadata enable-oslogin=TRUE \
    --boot-disk-size $GCPKMS_DISKSIZE
echo "Creating GCE instance ($GCPKMS_INSTANCENAME) ... end"
