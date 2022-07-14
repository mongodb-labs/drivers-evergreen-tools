# Delete GCE instance.
set -o errexit # Exit on first command error.
if [ -z "$INSTANCENAME" ]; then
    echo "Please set INSTANCENAME to GCE instance name"
    exit 1
fi

echo "Deleting GCE instance ($INSTANCENAME) ... begin"
yes | gcloud compute instances delete $INSTANCENAME \
    --zone=us-east1-b \
    --project csfle-poc
echo "Deleting GCE instance ($INSTANCENAME) ... end"
