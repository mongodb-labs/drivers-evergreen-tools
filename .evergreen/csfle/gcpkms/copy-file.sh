# Copy a file to or from a GCE instance.
if [ -z "$PROJECT" -o -z "$ZONE" -o -z "$SRC" -o -z "$DST" ]; then
    echo "Please set the following required environment variables"
    echo " PROJECT to the GCP project"
    echo " ZONE to the GCP zone"
    echo " SRC to the source file"
    echo " DST to the destination file"
    echo "To copy from or to a GCE host, use the host instance name"
    echo "Example: SRC=$INSTANCENAME:src.txt DST=. ./copy-file.sh"
    exit 1
fi

echo "Copying $SRC to $DST ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
gcloud compute scp $SRC $DST --scp-flag="-p"
echo "Copying $SRC to $DST ... end"