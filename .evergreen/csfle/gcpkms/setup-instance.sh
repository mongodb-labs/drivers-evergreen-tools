#!/usr/bin/env bash
# Setup a GCE instance.
set -o errexit # Exit on first command error.

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -z "$GCPKMS_GCLOUD" ] || [ -z "$GCPKMS_PROJECT" ] || [ -z "$GCPKMS_ZONE" ] || [ -z "$GCPKMS_INSTANCENAME" ]; then
    echo "Please set the following required environment variables"
    echo " GCPKMS_GCLOUD to the path of the gcloud binary"
    echo " GCPKMS_PROJECT to the GCP project"
    echo " GCPKMS_ZONE to the GCP zone"
    echo " GCPKMS_INSTANCENAME to the GCE instance name"
    exit 1
fi

# GCPKMS_SETUP_SCRIPT lets a caller provision with a different script, which
# drivers-tools' own tests use to reproduce an older provisioning.
DEFAULT_SETUP_SCRIPT="$SCRIPT_DIR/remote-scripts/setup-gce-instance.sh"
GCPKMS_SETUP_SCRIPT="${GCPKMS_SETUP_SCRIPT:-$DEFAULT_SETUP_SCRIPT}"
GCPKMS_SETUP_SCRIPT_NAME="$(basename "$GCPKMS_SETUP_SCRIPT")"

echo "Copying $GCPKMS_SETUP_SCRIPT_NAME to GCE instance ($GCPKMS_INSTANCENAME) ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
$GCPKMS_GCLOUD compute scp "$GCPKMS_SETUP_SCRIPT" "$GCPKMS_INSTANCENAME":~ \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --scp-flag="-p"
echo "Copying $GCPKMS_SETUP_SCRIPT_NAME to GCE instance ($GCPKMS_INSTANCENAME) ... end"

echo "Running $GCPKMS_SETUP_SCRIPT_NAME on GCE instance ($GCPKMS_INSTANCENAME) ... begin"
$GCPKMS_GCLOUD compute ssh "$GCPKMS_INSTANCENAME" \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --command "./$GCPKMS_SETUP_SCRIPT_NAME"
echo "Exit code of test-script is: $?"
echo "Running $GCPKMS_SETUP_SCRIPT_NAME on GCE instance ($GCPKMS_INSTANCENAME) ... end"

echo "Copying drivers-evergreen-tools to GCE instance ($GCPKMS_INSTANCENAME) ... begin"
# Ship this checkout so the instance runs the same revision that provisioned it.
# On failure start-mongodb.sh falls back to cloning the default branch, so this
# must not abort the task.
GCPKMS_ARCHIVE_DIR=$(mktemp -d)
if bash "$DRIVERS_TOOLS/.evergreen/make-drivers-tools-archive.sh" "$GCPKMS_ARCHIVE_DIR/drivers-evergreen-tools.tgz"; then
    $GCPKMS_GCLOUD compute scp "$GCPKMS_ARCHIVE_DIR/drivers-evergreen-tools.tgz" "$GCPKMS_INSTANCENAME":~ \
        --zone $GCPKMS_ZONE \
        --project $GCPKMS_PROJECT
else
    echo "WARNING: could not archive $DRIVERS_TOOLS; the instance will clone the default branch, which may not match this checkout."
fi
rm -rf "$GCPKMS_ARCHIVE_DIR"
echo "Copying drivers-evergreen-tools to GCE instance ($GCPKMS_INSTANCENAME) ... end"

echo "Copying start-mongodb.sh to GCE instance ($GCPKMS_INSTANCENAME) ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
$GCPKMS_GCLOUD compute scp $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/remote-scripts/start-mongodb.sh "$GCPKMS_INSTANCENAME":~ \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --scp-flag="-p"
echo "Copying start-mongodb.sh to GCE instance ($GCPKMS_INSTANCENAME) ... end"

echo "Running start-mongodb.sh on GCE instance ($GCPKMS_INSTANCENAME) ... begin"
$GCPKMS_GCLOUD compute ssh "$GCPKMS_INSTANCENAME" \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --command "./start-mongodb.sh"
echo "Exit code of test-script is: $?"
echo "Running start-mongodb.sh on GCE instance ($GCPKMS_INSTANCENAME) ... end"
