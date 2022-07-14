# Setup a GCE instance.
set -o errexit # Exit on first command error.
if [ -z "$INSTANCENAME" ]; then
    echo "Please set INSTANCENAME to GCE instance name"
    exit 1
fi

echo "Copying setup-gce-instance.sh to GCE instance ($INSTANCENAME) ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
gcloud compute scp ./remote-scripts/setup-gce-instance.sh "$INSTANCENAME":~ \
    --zone us-east1-b \
    --project csfle-poc \
    --scp-flag="-p"
echo "Copying setup-gce-instance.sh to GCE instance ($INSTANCENAME) ... end"

echo "Running setup-gce-instance.sh on GCE instance ($INSTANCENAME) ... begin"
gcloud compute ssh "$INSTANCENAME" \
    --zone us-east1-b \
    --project csfle-poc \
    --command "./setup-gce-instance.sh"
echo "Exit code of test-script is: $?"
echo "Running setup-gce-instance.sh on GCE instance ($INSTANCENAME) ... end"

