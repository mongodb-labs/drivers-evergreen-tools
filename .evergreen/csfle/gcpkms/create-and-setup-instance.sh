# Create and setup a GCE instance.
set -o errexit # Exit on first command error.
if [ -z "$KEYFILE" -o -z "$DRIVERS_TOOLS" -o -z "$SERVICEACCOUNT" ]; then
    echo "Please set the following required environment variables"
    echo " KEYFILE to the JSON file for the service account"
    echo " DRIVERS_TOOLS to the path of the drivers-evergreen-tools directory"
    echo " SERVICEACCOUNT to a GCP service account used to create and attach to the GCE instance"
    exit 1
fi

# Set defaults.
export PROJECT=${PROJECT:-"csfle-poc"}
export ZONE=${ZONE:-"us-east1-b"}
export IMAGEPROJECT=${IMAGEPROJECT:-"debian-cloud"}
export IMAGEFAMILY=${IMAGEFAMILY:-"debian-11"}
export MACHINETYPE=${MACHINETYPE:-"e2-micro"}

# download-gcloud.sh sets GCLOUD.
echo "download-gcloud.sh ... begin"
. $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/download-gcloud.sh
echo "download-gcloud.sh ... end"

$GCLOUD auth activate-service-account --key-file $KEYFILE

# create-instance.sh sets INSTANCENAME.
echo "create-instance.sh ... begin"
. $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/create-instance.sh
echo "create-instance.sh ... end"

echo "setup-instance.sh ... begin"
. $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/setup-instance.sh
echo "setup-instance.sh ... end"

echo "GCLOUD: $GCLOUD" > testgcpkms-expansions.yml
echo "INSTANCENAME: $INSTANCENAME" >> testgcpkms-expansions.yml
