# Run a command on a remote GCE instance.
if [ -z "$INSTANCENAME" ]; then
    echo "Please set INSTANCENAME to GCE instance name"
    exit 1
fi
if [ -z "$CMD" ]; then
    echo "Please set CMD to a command to run on GCE instance."
    exit 1
fi

echo "Running '$CMD' on GCE instance ... begin"
gcloud compute ssh "$INSTANCENAME" \
    --zone us-east1-b \
    --project csfle-poc \
    --command $CMD
echo "Running '$CMD' on GCE instance ... end"