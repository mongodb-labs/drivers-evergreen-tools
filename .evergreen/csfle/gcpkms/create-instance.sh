# Create a GCE instance.
set -o errexit # Exit on first command error.
INSTANCENAME="instancename-$RANDOM"
SERVICEACCOUNT="test-service-account-kms@csfle-poc.iam.gserviceaccount.com"
IMAGEPROJECT="debian-cloud"
IMAGEFAMILY="debian-11"
# Store INSTANCENAME so Evergreen can delete instance later.
echo "INSTANCENAME: $INSTANCENAME" > gcpkms-expansions.yml

# Create GCE instance.
echo "Creating GCE instance ($INSTANCENAME) ... begin"
echo "Using service account: $SERVICEACCOUNT"
gcloud compute instances create $INSTANCENAME \
    --zone=us-east1-b \
    --project csfle-poc \
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