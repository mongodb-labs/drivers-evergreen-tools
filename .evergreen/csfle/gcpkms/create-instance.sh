# Create a GCE instance.
set -o errexit # Exit on first command error.
if [ -z "$DRIVERS_TOOLS" -o -z "$GCLOUD" -o -z "$PROJECT" -o -z "$ZONE" -o -z "$SERVICEACCOUNT" ]; then
    echo "Please set the following required environment variables"
    echo " DRIVERS_TOOLS to the path of the drivers-evergreen-tools directory"
    echo " GCLOUD to the path of the gcloud binary"
    echo " PROJECT to the GCP project"
    echo " ZONE to the GCP zone"
    echo " SERVICEACCOUNT to a GCP service account used to create and attach to the GCE instance"
    exit 1
fi
INSTANCENAME="instancename-$RANDOM"
IMAGEPROJECT=${IMAGEPROJECT:-"debian-cloud"}
IMAGEFAMILY=${IMAGEFAMILY:-"debian-11"}
MACHINETYPE=${MACHINETYPE:-"e2-micro"}
# Store INSTANCENAME so Evergreen can delete instance later.
echo "INSTANCENAME: $INSTANCENAME" > gcpkms-expansions.yml

# Create GCE instance.
echo "Creating GCE instance ($INSTANCENAME) ... begin"
echo "Using service account: $SERVICEACCOUNT"
# Add cloudkms scope for making KMS requests.
# Add compute scope so instance can self-delete.
$GCLOUD compute instances create $INSTANCENAME \
    --zone $ZONE \
    --project $PROJECT \
    --machine-type $MACHINETYPE \
    --service-account $SERVICEACCOUNT \
    --image-project $IMAGEPROJECT \
    --image-family $IMAGEFAMILY \
    --metadata-from-file=startup-script=$DRIVERS_TOOLS/.evergreen/csfle/gcpkms/remote-scripts/startup.sh \
    --scopes https://www.googleapis.com/auth/cloudkms,https://www.googleapis.com/auth/compute
echo "Creating GCE instance ($INSTANCENAME) ... end"

# Sleep for 60 seconds for VM to finish booting.
# Otherwise SSH may fail. See https://cloud.google.com/compute/docs/troubleshooting/troubleshooting-ssh.
echo "Sleeping for 60 seconds ... begin"
sleep 60
echo "Sleeping for 60 seconds ... end"