#!/usr/bin/env bash
# Create and setup a GCE instance.
# On success, creates testgcpkms-expansions.yml expansions
set -o errexit # Exit on first command error.

CURR_DIR=$(pwd)
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

pushd $SCRIPT_DIR

# Handle secrets file location.
GCPKMS_SECRETS_FILE=${GCPKMS_SECRETS_FILE:-./secrets-export.sh}

# Handle secrets from vault.
if [ -f "$GCPKMS_SECRETS_FILE" ]; then
  echo "Sourcing secrets"
  source $GCPKMS_SECRETS_FILE
fi
if [ -z "${GCPKMS_SERVICEACCOUNT:-}" ]; then
    . ./setup-secrets.sh
fi

# Write the keyfile content to a local JSON path.
if [ -n "$GCPKMS_KEYFILE_CONTENT" ]; then
    export GCPKMS_KEYFILE=/tmp/testgcpkms_key_file.json
    # convert content from base64 to JSON and write to file
    echo ${GCPKMS_KEYFILE_CONTENT} | base64 --decode > $GCPKMS_KEYFILE
fi

if [ -z "$GCPKMS_KEYFILE" -o -z "$GCPKMS_SERVICEACCOUNT" ]; then
    echo "Please set the following required environment variables"
    echo " GCPKMS_KEYFILE to the JSON file for the service account"
    echo " GCPKMS_SERVICEACCOUNT to a GCP service account used to create and attach to the GCE instance"
    exit 1
fi

# Set 600 permissions on private key file. Otherwise ssh / scp may error with permissions "are too open".
chmod 600 $GCPKMS_KEYFILE

# Set defaults.
export GCPKMS_PROJECT=${GCPKMS_PROJECT:-"devprod-drivers"}
export GCPKMS_ZONE=${GCPKMS_ZONE:-"us-east1-b"}
export GCPKMS_IMAGEPROJECT=${GCPKMS_IMAGEPROJECT:-"debian-cloud"}
export GCPKMS_IMAGEFAMILY=${GCPKMS_IMAGEFAMILY:-"debian-11"}
export GCPKMS_MACHINETYPE=${GCPKMS_MACHINETYPE:-"e2-micro"}
export GCPKMS_DISKSIZE=${GCPKMS_DISKSIZE:-"20gb"}

# download-gcloud.sh sets GCPKMS_GCLOUD.
echo "download-gcloud.sh ... begin"
. $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/download-gcloud.sh
echo "download-gcloud.sh ... end"

$GCPKMS_GCLOUD auth activate-service-account --key-file $GCPKMS_KEYFILE

# create-instance.sh sets INSTANCENAME.
echo "create-instance.sh ... begin"
. $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/create-instance.sh
echo "create-instance.sh ... end"

# Echo expansions required for delete-instance.sh. If the remaining setup fails, delete-instance.sh can still clean up resources.
EXPANSION_FILE="$CURR_DIR/testgcpkms-expansions.yml"
echo "GCPKMS_GCLOUD: $GCPKMS_GCLOUD" > $EXPANSION_FILE
echo "GCPKMS_INSTANCENAME: $GCPKMS_INSTANCENAME" >> $EXPANSION_FILE
echo "GCPKMS_PROJECT: $GCPKMS_PROJECT" >> $EXPANSION_FILE
echo "GCPKMS_ZONE: $GCPKMS_ZONE" >> $EXPANSION_FILE
if [ -f "$GCPKMS_SECRETS_FILE" ]; then
    echo "export GCPKMS_GCLOUD=$GCPKMS_GCLOUD" >> $GCPKMS_SECRETS_FILE
    echo "export GCPKMS_INSTANCENAME=$GCPKMS_INSTANCENAME" >> $GCPKMS_SECRETS_FILE
    echo "export GCPKMS_PROJECT=$GCPKMS_PROJECT" >> $GCPKMS_SECRETS_FILE
    echo "export GCPKMS_ZONE=$GCPKMS_ZONE" >> $GCPKMS_SECRETS_FILE
fi

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

# Add expiration to the SSH key created. This is a fallback to identify old keys in case the SSH key is unable to be deleted in delete-instance.sh.
echo "Adding expiration time to SSH key ... begin"
$GCPKMS_GCLOUD compute os-login ssh-keys update --key-file ~/.ssh/google_compute_engine.pub --ttl 7200s
echo "Adding expiration time to SSH key ... end"

SETUP_INSTANCE=${GCPKMS_SETUP_INSTANCE:-$DRIVERS_TOOLS/.evergreen/csfle/gcpkms/setup-instance.sh}
echo "setup-instance.sh ... begin"
. $SETUP_INSTANCE
echo "setup-instance.sh ... end"
