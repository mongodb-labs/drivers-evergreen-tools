# Setup a GCE instance.
set -o errexit # Exit on first command error.
if [ -z "$DRIVERS_TOOLS" -o -z "$GCLOUD" -o -z "$PROJECT" -o -z "$ZONE" -o -z "$INSTANCENAME" ]; then
    echo "Please set the following required environment variables"
    echo " DRIVERS_TOOLS to the path of the drivers-evergreen-tools directory"
    echo " GCLOUD to the path of the gcloud binary"
    echo " PROJECT to the GCP project"
    echo " ZONE to the GCP zone"
    echo " INSTANCENAME to the GCE instance name"
    exit 1
fi

echo "Copying setup-gce-instance.sh to GCE instance ($INSTANCENAME) ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
gcloud compute scp $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/remote-scripts/setup-gce-instance.sh "$INSTANCENAME":~ \
    --zone $ZONE \
    --project $PROJECT \
    --scp-flag="-p"
echo "Copying setup-gce-instance.sh to GCE instance ($INSTANCENAME) ... end"

echo "Running setup-gce-instance.sh on GCE instance ($INSTANCENAME) ... begin"
gcloud compute ssh "$INSTANCENAME" \
    --zone $ZONE \
    --project $PROJECT \
    --command "./setup-gce-instance.sh"
echo "Exit code of test-script is: $?"
echo "Running setup-gce-instance.sh on GCE instance ($INSTANCENAME) ... end"

