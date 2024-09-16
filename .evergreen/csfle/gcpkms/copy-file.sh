#!/usr/bin/env bash
# Copy a file to or from a GCE instance.
set -o errexit # Exit on first command error.

VARLIST=(
GCPKMS_GCLOUD
GCPKMS_PROJECT
GCPKMS_ZONE
GCPKMS_SRC
GCPKMS_DST
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

echo "Copying $GCPKMS_SRC to $GCPKMS_DST ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
$GCPKMS_GCLOUD compute scp $GCPKMS_SRC $GCPKMS_DST \
    --scp-flag="-p" \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT
echo "Copying $GCPKMS_SRC to $GCPKMS_DST ... end"
