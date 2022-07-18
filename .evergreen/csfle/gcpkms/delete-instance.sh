# Delete GCE instance.
set -o errexit # Exit on first command error.
if [ -z "$GCLOUD" -o -z "$PROJECT" -o -z "$ZONE" -o -z "$INSTANCENAME" ]; then
    echo "Please set the following required environment variables"
    echo " GCLOUD to the path of the gcloud binary"
    echo " PROJECT to the GCP project"
    echo " ZONE to the GCP zone"
    echo " INSTANCENAME to the GCE instance name"
    exit 1
fi

echo "Deleting GCE instance ($INSTANCENAME) ... begin"
yes | $GCLOUD compute instances delete $INSTANCENAME \
    --zone $ZONE \
    --project $PROJECT
echo "Deleting GCE instance ($INSTANCENAME) ... end"
