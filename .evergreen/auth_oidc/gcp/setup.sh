#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Handle secrets from vault.
rm -f secrets-export.sh
. ./setup-secrets.sh

########################
# Start an Atlas Cluster

# Get the utility functions
. ../../atlas/atlas-utils.sh

# Generate a random cluster name.
# See: https://docs.atlas.mongodb.com/reference/atlas-limits/#label-limits
DEPLOYMENT_NAME="$RANDOM-DRIVERGCP"
echo "export CLUSTER_NAME=$DEPLOYMENT_NAME" >> "$DRIVERS_TOOLS/.evergreen/atlas/secrets-export.sh"

# Set the create cluster configuration.
DEPLOYMENT_DATA=$(cat <<EOF
{
  "autoScaling" : {
    "autoIndexingEnabled" : false,
    "compute" : {
      "enabled" : true,
      "scaleDownEnabled" : true
    },
    "diskGBEnabled" : true
  },
  "backupEnabled" : false,
  "biConnector" : {
    "enabled" : false,
    "readPreference" : "secondary"
  },
  "clusterType" : "REPLICASET",
  "diskSizeGB" : 10.0,
  "encryptionAtRestProvider" : "NONE",
  "mongoDBMajorVersion" : "7.0",
  "name" : "${DEPLOYMENT_NAME}",
  "numShards" : 1,
  "paused" : false,
  "pitEnabled" : false,
  "providerBackupEnabled" : false,
  "providerSettings" : {
    "providerName" : "AWS",
    "autoScaling" : {
      "compute" : {
        "maxInstanceSize" : "M20",
        "minInstanceSize" : "M10"
      }
    },
    "diskIOPS" : 3000,
    "encryptEBSVolume" : true,
    "instanceSizeName" : "M10",
    "regionName" : "US_EAST_1",
    "volumeType" : "STANDARD"
  },
  "replicationFactor" : 3,
  "rootCertType" : "ISRGROOTX1",
  "terminationProtectionEnabled" : false,
  "versionReleaseSystem" : "LTS"
}
EOF
)
export DEPLOYMENT_DATA

export ATLAS_PUBLIC_API_KEY=$OIDC_ATLAS_PUBLIC_API_KEY
export ATLAS_PRIVATE_API_KEY=$OIDC_ATLAS_PRIVATE_API_KEY
export ATLAS_GROUP_ID=$OIDC_ATLAS_GROUP_ID

create_deployment

########################
# Set up the GCE instance.

# Set up variables for GCPKMS scripts.
export GCPKMS_SECRETS_FILE="$SCRIPT_DIR/secrets-export.sh"
export GCPKMS_SERVICEACCOUNT=$GCPOIDC_SERVICEACCOUNT
export GCPKMS_MACHINE=$GCPOIDC_MACHINE
export GCPKMS_SETUP_INSTANCE="$SCRIPT_DIR/setup-instance.sh"

# Write the keyfile content to a local JSON path.
export GCPKMS_KEYFILE=/tmp/testgcpkms_key_file.json
# convert content from base64 to JSON and write to file
echo ${GCPOIDC_KEYFILE_CONTENT} | base64 --decode > $GCPKMS_KEYFILE

# Create the instance using the script.
bash $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/create-and-setup-instance.sh

########################
# Wait for the Atlas Cluster
URI=$(check_deployment)

cat <<EOF >> "secrets-export.sh"
export MONGODB_URI="$URI"
export MONGODB_URI_SINGLE="$URI/?authMechanism=MONGODB-OIDC&authSource=%24external&authMechanismProperties=ENVIRONMENT:gcp,TOKEN_RESOURCE:$GCPOIDC_AUDIENCE"
export OIDC_ADMIN_USER=$GCPOIDC_ATLAS_USER
export OIDC_ADMIN_PWD=$GCPOIDC_ATLAS_PASSWORD
EOF

########################
# Run the self test.
source ./secrets-export.sh
echo "Copying secrets file to GCE instance ($GCPKMS_INSTANCENAME) ... begin"
$GCPKMS_GCLOUD compute scp $DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/secrets-export.sh "$GCPKMS_INSTANCENAME":~ \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --scp-flag="-p"
echo "Copying secrets file to GCE instance ($GCPKMS_INSTANCENAME) ... end"

echo "Running run-self-test.sh on GCE instance ($GCPKMS_INSTANCENAME) ... begin"
$GCPKMS_GCLOUD compute ssh "$GCPKMS_INSTANCENAME" \
    --zone $GCPKMS_ZONE \
    --project $GCPKMS_PROJECT \
    --command "./run-self-test.sh"
echo "Exit code of test-script is: $?"
echo "Running run-self-test.sh on GCE instance ($GCPKMS_INSTANCENAME) ... end"

popd
