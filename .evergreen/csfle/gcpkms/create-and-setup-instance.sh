# Create and setup a GCE instance.
# On success, creates testgcpkms-expansions.yml expansions 
set -o errexit # Exit on first command error.
if [ -z "$GCPKMS_KEYFILE" -o -z "$GCPKMS_DRIVERS_TOOLS" -o -z "$GCPKMS_SERVICEACCOUNT" ]; then
    echo "Please set the following required environment variables"
    echo " GCPKMS_KEYFILE to the JSON file for the service account"
    echo " GCPKMS_DRIVERS_TOOLS to the path of the drivers-evergreen-tools directory"
    echo " GCPKMS_SERVICEACCOUNT to a GCP service account used to create and attach to the GCE instance"
    exit 1
fi

# Set defaults.
export GCPKMS_PROJECT=${GCPKMS_PROJECT:-"devprod-drivers"}
export GCPKMS_ZONE=${GCPKMS_ZONE:-"us-east1-b"}
export GCPKMS_IMAGEPROJECT=${GCPKMS_IMAGEPROJECT:-"debian-cloud"}
export GCPKMS_IMAGEFAMILY=${GCPKMS_IMAGEFAMILY:-"debian-11"}
export GCPKMS_MACHINETYPE=${GCPKMS_MACHINETYPE:-"e2-micro"}
export GCPKMS_DISKSIZE=${GCPKMS_DISKSIZE:-"20gb"}

# download-gcloud.sh sets GCPKMS_GCLOUD.
echo "download-gcloud.sh ... begin"
. $GCPKMS_DRIVERS_TOOLS/.evergreen/csfle/gcpkms/download-gcloud.sh
echo "download-gcloud.sh ... end"

$GCPKMS_GCLOUD auth activate-service-account --key-file $GCPKMS_KEYFILE

# create-instance.sh sets INSTANCENAME.
echo "create-instance.sh ... begin"
. $GCPKMS_DRIVERS_TOOLS/.evergreen/csfle/gcpkms/create-instance.sh
echo "create-instance.sh ... end"

# Wait for a maximum of five minutes for VM to finish booting.
# Otherwise SSH may fail. See https://cloud.google.com/compute/docs/troubleshooting/troubleshooting-ssh.
wait_for_server () {
    for i in $(seq 300); do
        # The first `gcloud compute ssh` creates an SSH key pair and stores the public key in the Google Account.
        # The public key is deleted from the Google Account in delete-instance.sh.
        if SSHOUTPUT=$($GCPKMS_GCLOUD compute ssh "$GCPKMS_INSTANCENAME" --zone $GCPKMS_ZONE --project $GCPKMS_PROJECT --command "echo 'ping' --ssh-flag='-o ConnectTimeout=10'" 2>&1); then
            echo "ssh succeeded"
            return 0
        else
            sleep 1
        fi
    done
    echo "failed to ssh into '$GCPKMS_INSTANCENAME'. Output of last attempt: $SSHOUTPUT"
    return 1
}
echo "waiting for server to start ... begin"
wait_for_server
echo "waiting for server to start ... end"

echo "setup-instance.sh ... begin"
. $GCPKMS_DRIVERS_TOOLS/.evergreen/csfle/gcpkms/setup-instance.sh
echo "setup-instance.sh ... end"

echo "GCPKMS_GCLOUD: $GCPKMS_GCLOUD" > testgcpkms-expansions.yml
echo "GCPKMS_INSTANCENAME: $GCPKMS_INSTANCENAME" >> testgcpkms-expansions.yml
echo "GCPKMS_PROJECT: $GCPKMS_PROJECT" >> testgcpkms-expansions.yml
echo "GCPKMS_ZONE: $GCPKMS_ZONE" >> testgcpkms-expansions.yml
