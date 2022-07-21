# Copy a file to or from a GCE instance.
set -o errexit # Exit on first command error.
set -o xtrace
if [ -z "$GCPKMS_GCLOUD" -o -z "$GCPKMS_PROJECT" -o -z "$GCPKMS_ZONE" -o -z "$GCPKMS_SRC" -o -z "$GCPKMS_DST" ]; then
    echo "Please set the following required environment variables"
    echo " GCPKMS_GCLOUD to the path of the gcloud binary"
    echo " GCPKMS_PROJECT to the GCP project"
    echo " GCPKMS_ZONE to the GCP zone"
    echo " GCPKMS_SRC to the source file"
    echo " GCPKMS_DST to the destination file"
    echo "To copy from or to a GCE host, use the host instance name"
    echo "Example: GCPKMS_SRC=$GCPKMS_INSTANCENAME:src.txt GCPKMS_DST=. ./copy-file.sh"
    exit 1
fi

echo "Copying $GCPKMS_SRC to $GCPKMS_DST ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
$GCPKMS_GCLOUD compute scp $GCPKMS_SRC $GCPKMS_DST \
    --scp-flag="-p" \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT
echo "Copying $GCPKMS_SRC to $GCPKMS_DST ... end"