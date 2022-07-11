# Create a GCE instance, copy test files, and run test.
set -o errexit # Exit on first command error.
INSTANCENAME="instancename-$RANDOM"
SERVICEACCOUNT="test-service-account-kms@csfle-poc.iam.gserviceaccount.com"
# Store INSTANCENAME so Evergreen can delete instance later.
echo "INSTANCENAME: $INSTANCENAME" > gce-expansions.yml

# Create GCE instance.
echo "Creating GCE instance ($INSTANCENAME) ... begin"
echo "Using service account: $SERVICEACCOUNT"
gcloud compute instances create $INSTANCENAME \
    --zone=us-east1-b \
    --project csfle-poc \
    --machine-type e2-micro \
    --service-account $SERVICEACCOUNT
echo "Creating GCE instance ($INSTANCENAME) ... end"

# Sleep for 60 seconds for VM to finish booting.
# Otherwise SSH may fail. See https://cloud.google.com/compute/docs/troubleshooting/troubleshooting-ssh.
echo "Sleeping for 60 seconds ... begin"
sleep 60
echo "Sleeping for 60 seconds ... end"

# Copy test files.
echo "Copying files to GCE instance ($INSTANCENAME) ... begin"
cat << EOT > test-script.sh
    echo "Running test on GCE instance. Exiting with $TEST_SCRIPT_EXIT_CODE";
    echo "Drivers will provide this script along with other files necessary to test."
    exit $TEST_SCRIPT_EXIT_CODE
EOT
chmod u+x test-script.sh
# Copy files to test. Use "-p" to preserve execute mode.
gcloud compute scp ./test-script.sh "$INSTANCENAME":~ \
    --zone us-east1-b \
    --project csfle-poc \
    --scp-flag="-p"
echo "Copying files to GCE instance ($INSTANCENAME) ... end"

# Run test.
echo "Running test on GCE instance ($INSTANCENAME) ... begin"
gcloud compute ssh "$INSTANCENAME" \
    --zone us-east1-b \
    --project csfle-poc \
    --command "./test-script.sh"
echo "Exit code of test-script is: $?"
echo "Running test on GCE instance ($INSTANCENAME) ... end"

# Delete GCE instance.
echo "Deleting GCE instance ($INSTANCENAME) ... begin"
echo "Using service account: $SERVICEACCOUNT"
yes | gcloud compute instances delete $INSTANCENAME \
    --zone=us-east1-b \
    --project csfle-poc \
    --delete-disks=all
echo "Deleting GCE instance ($INSTANCENAME) ... end"