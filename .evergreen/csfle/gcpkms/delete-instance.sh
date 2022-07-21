# Delete GCE instance.
set -o errexit # Exit on first command error.
set -o xtrace
if [ -z "$GCPKMS_GCLOUD" -o -z "$GCPKMS_PROJECT" -o -z "$GCPKMS_ZONE" -o -z "$GCPKMS_INSTANCENAME" ]; then
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
