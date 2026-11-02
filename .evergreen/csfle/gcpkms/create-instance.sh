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

# Label the instance per the MongoDB Cloud Tag Policy (DRIVERS-3712).
# GCP labels are lowercase-only, so the owner default omits @mongodb.com.
MONGODB_OWNER_TAG="${MONGODB_OWNER_TAG:-client-libraries-managers}"
MONGODB_ENV_TAG="${MONGODB_ENV_TAG:-dev}"

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
    --labels "mongodb-owner=$MONGODB_OWNER_TAG,mongodb-env=$MONGODB_ENV_TAG" \
    --boot-disk-size $GCPKMS_DISKSIZE
echo "Creating GCE instance ($GCPKMS_INSTANCENAME) ... end"

# --labels above only reaches the VM; label the boot disk too (DRIVERS-3712).
# A failed update deletes the instance: teardown metadata is persisted only
# after this script returns.
if ! $GCPKMS_GCLOUD compute disks update "$GCPKMS_INSTANCENAME" \
    --zone "$GCPKMS_ZONE" --project "$GCPKMS_PROJECT" \
    --update-labels "mongodb-owner=$MONGODB_OWNER_TAG,mongodb-env=$MONGODB_ENV_TAG"; then
  echo "Labeling the boot disk failed; deleting instance ${GCPKMS_INSTANCENAME}" 1>&2
  $GCPKMS_GCLOUD compute instances delete "$GCPKMS_INSTANCENAME" \
      --zone "$GCPKMS_ZONE" --project "$GCPKMS_PROJECT" --quiet || true
  exit 1
fi

# Verify labels when requested (DRIVERS-3712). verify_cloud_tags exits the
# sourcing shell, so on failure delete the instance (and its boot disk)
# before exiting.
if [ -n "${VERIFY_MONGODB_TAGS:-}" ]; then
  if ! (
    . "$DRIVERS_TOOLS"/.evergreen/verify-tags.sh
    verify_cloud_tags "GCE instance ${GCPKMS_INSTANCENAME}" \
      "$($GCPKMS_GCLOUD compute instances describe "${GCPKMS_INSTANCENAME}" \
        --zone "${GCPKMS_ZONE}" --project "${GCPKMS_PROJECT}" \
        --format "json(labels)")" "labels"
    verify_cloud_tags "GCE boot disk ${GCPKMS_INSTANCENAME}" \
      "$($GCPKMS_GCLOUD compute disks describe "${GCPKMS_INSTANCENAME}" \
        --zone "${GCPKMS_ZONE}" --project "${GCPKMS_PROJECT}" \
        --format "json(labels)")" "labels"
  ); then
    echo "Label verification failed; deleting instance ${GCPKMS_INSTANCENAME}" 1>&2
    $GCPKMS_GCLOUD compute instances delete "$GCPKMS_INSTANCENAME" \
        --zone "$GCPKMS_ZONE" --project "$GCPKMS_PROJECT" --quiet || true
    exit 1
  fi
fi
