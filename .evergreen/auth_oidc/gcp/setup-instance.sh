#!/usr/bin/env bash
# Setup a GCE instance for MONGODB-OIDC test.
set -o errexit # Exit on first command error.

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

VARLIST=(
GCPKMS_GCLOUD
GCPKMS_PROJECT
GCPKMS_ZONE
GCPKMS_INSTANCENAME
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

echo "Copying setup-gce-instance.sh to GCE instance ($GCPKMS_INSTANCENAME) ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
$GCPKMS_GCLOUD compute scp $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/remote-scripts/setup-gce-instance.sh "$GCPKMS_INSTANCENAME":~ \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --scp-flag="-p"
echo "Copying setup-gce-instance.sh to GCE instance ($GCPKMS_INSTANCENAME) ... end"

echo "Running setup-gce-instance.sh on GCE instance ($GCPKMS_INSTANCENAME) ... begin"
$GCPKMS_GCLOUD compute ssh "$GCPKMS_INSTANCENAME" \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --command "./setup-gce-instance.sh"
echo "Exit code of test-script is: $?"
echo "Running setup-gce-instance.sh on GCE instance ($GCPKMS_INSTANCENAME) ... end"

echo "Copying test files to GCE instance ($GCPKMS_INSTANCENAME) ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
$GCPKMS_GCLOUD compute scp $DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/remote-scripts/run-self-test.sh "$GCPKMS_INSTANCENAME":~ \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --scp-flag="-p"
$GCPKMS_GCLOUD compute scp $DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/remote-scripts/test.py "$GCPKMS_INSTANCENAME":~ \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --scp-flag="-p"
echo "Copying test files to GCE instance ($GCPKMS_INSTANCENAME) ... end"
