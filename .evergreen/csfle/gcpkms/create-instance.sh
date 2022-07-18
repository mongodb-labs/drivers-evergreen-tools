# Create a GCE instance.
set -o errexit # Exit on first command error.
if [ -z "$PROJECT" -o -z "$ZONE" ]; then
    echo "Please set the following required environment variables"
    echo " PROJECT to the GCP project"
    echo " ZONE to the GCP zone"
    exit 1
fi
INSTANCENAME="instancename-$RANDOM"
SERVICEACCOUNT="d2377-937@csfle-poc.iam.gserviceaccount.com"
IMAGEPROJECT="debian-cloud"
IMAGEFAMILY="debian-11"
# Store INSTANCENAME so Evergreen can delete instance later.
echo "INSTANCENAME: $INSTANCENAME" > gcpkms-expansions.yml

# Create GCE instance.
echo "Creating GCE instance ($INSTANCENAME) ... begin"
echo "Using service account: $SERVICEACCOUNT"
gcloud compute instances create $INSTANCENAME \
    --zone $ZONE \
    --project $PROJECT \
    --machine-type e2-micro \
    --service-account $SERVICEACCOUNT \
    --image-project $IMAGEPROJECT \
    --image-family $IMAGEFAMILY \
    --scopes https://www.googleapis.com/auth/cloudkms
echo "Creating GCE instance ($INSTANCENAME) ... end"

# Sleep for 60 seconds for VM to finish booting.
# Otherwise SSH may fail. See https://cloud.google.com/compute/docs/troubleshooting/troubleshooting-ssh.
echo "Sleeping for 60 seconds ... begin"
sleep 60
echo "Sleeping for 60 seconds ... end"