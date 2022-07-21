# Create a GCE instance.
set -o errexit # Exit on first command error.
set -o xtrace
if [ -z "$GCPKMS_DRIVERS_TOOLS" -o \
     -z "$GCPKMS_GCLOUD" -o \
     -z "$GCPKMS_PROJECT" -o \
     -z "$GCPKMS_ZONE" -o \
     -z "$GCPKMS_SERVICEACCOUNT" -o \
     -z "$GCPKMS_IMAGEPROJECT" -o \
     -z "$GCPKMS_IMAGEFAMILY" -o \
     -z "$GCPKMS_MACHINETYPE" ]; then
    echo "Please set the following required environment variables"
    echo " GCPKMS_DRIVERS_TOOLS to the path of the drivers-evergreen-tools directory"
    echo " GCPKMS_GCLOUD to the path of the gcloud binary"
    echo " GCPKMS_PROJECT to the GCP project"
    echo " GCPKMS_ZONE to the GCP zone"
    echo " GCPKMS_SERVICEACCOUNT to a GCP service account used to create and attach to the GCE instance"
    echo " GCPKMS_IMAGEPROJECT to the GCE image project (e.g. debian-cloud)"
    echo " GCPKMS_IMAGEFAMILY to the GCE image family (e.g. debian-11)"
    echo " GCPKMS_MACHINETYPE to the GCE machine type (e.g. e2-micro)"
    exit 1
fi
GCPKMS_INSTANCENAME="instancename-$RANDOM"

# Create GCE instance.
echo "Creating GCE instance ($GCPKMS_INSTANCENAME) ... begin"
echo "Using service account: $GCPKMS_SERVICEACCOUNT"
# Add cloudkms scope for making KMS requests.
# Add compute scope so instance can self-delete.
$GCPKMS_GCLOUD compute instances create $GCPKMS_INSTANCENAME \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --machine-type $GCPKMS_MACHINETYPE \
    --service-account $GCPKMS_SERVICEACCOUNT \
    --image-project $GCPKMS_IMAGEPROJECT \
    --image-family $GCPKMS_IMAGEFAMILY \
    --metadata-from-file=startup-script=$GCPKMS_DRIVERS_TOOLS/.evergreen/csfle/gcpkms/remote-scripts/startup.sh \
    --scopes https://www.googleapis.com/auth/cloudkms,https://www.googleapis.com/auth/compute
echo "Creating GCE instance ($GCPKMS_INSTANCENAME) ... end"
