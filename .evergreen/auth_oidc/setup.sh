#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Get the secrets
if [ -f ./secrets-export.sh ]; then
    echo "Sourcing secrets"
    source ./secrets-export.sh
else
    . ./setup-secrets.sh
fi

# Start an Atlas Cluster

# Get the utility functions
. ../atlas/atlas-utils.sh

# Generate a random cluster name.
# See: https://docs.atlas.mongodb.com/reference/atlas-limits/#label-limits
DEPLOYMENT_NAME="$RANDOM-DRIVERTEST"
echo "export CLUSTER_NAME=$DEPLOYMENT_NAME" >> "secrets-export.sh"

# Set the create cluster configuration.
export DEPLOYMENT_DATA=$(cat <<EOF
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

export ATLAS_PUBLIC_API_KEY=$OIDC_ATLAS_PUBLIC_API_KEY
export ATLAS_PRIVATE_API_KEY=$OIDC_ATLAS_PRIVATE_API_KEY
export ATLAS_GROUP_ID=$OIDC_ATLAS_GROUP_ID

create_deployment

# If on Linux, start a local server and write OIDC_URI_MULTI to secrets file.
if [ "$(uname -s)" = "Linux" ]; then
    . ./activate-authoidcvenv.sh
    python oidc_write_orchestration.py
    bash run-orchestration.sh
    $MONGODB_BINARIES/mongosh -f ./setup_oidc.js "mongodb://127.0.0.1:27017/directConnection=true&serverSelectionTimeoutMS=10000"
    echo "export OIDC_URI_MULTI=mongodb//:27018/?directConnection=true" >> "secrets-export.sh"
fi

# Wait for the Atlas Cluster
OIDC_URI_SINGLE=$(check_deployment)
echo "export OIDC_URI_SINGLE=$OIDC_URI_SINGLE" >> "secrets-export.sh"
