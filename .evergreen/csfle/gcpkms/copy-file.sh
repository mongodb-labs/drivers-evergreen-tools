# Copy a file to or from a GCE instance.
if [ -z "$SRC" -o -z "$DST" ]; then
    echo "Please set SRC to source file and DST to destination file."
    exit 1
fi

echo "Copying $SRC to $DST ... begin"
# Copy files to test. Use "-p" to preserve execute mode.
gcloud compute scp $SRC $DST --scp-flag="-p"
echo "Copying $SRC to $DST ... end"