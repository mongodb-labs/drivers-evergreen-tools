# Run a command on a remote GCE instance.
set -o errexit # Exit on first command error.
if [ -z "$GCLOUD" -o -z "$PROJECT" -o -z "$ZONE" -o -z "$INSTANCENAME" -o -z "$CMD" ]; then
    echo "Please set the following required environment variables"
    echo " GCLOUD to the path of the gcloud binary"
    echo " PROJECT to the GCP project"
    echo " ZONE to the GCP zone"
    echo " INSTANCENAME to the GCE instance name"
    echo " CMD to a command to run on GCE instance"
    exit 1
fi

echo "Running '$CMD' on GCE instance ... begin"
$GCLOUD compute ssh "$INSTANCENAME" \
    --zone $ZONE \
    --project $PROJECT \
    --command "$CMD"
echo "Running '$CMD' on GCE instance ... end"