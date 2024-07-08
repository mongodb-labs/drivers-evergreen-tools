#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh
pushd $SCRIPT_DIR

# Ensure Azure Functions Core Tools is/can be installed.
DOCS_URL=https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local
OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
if ! command -v func &> /dev/null; then
  if [ "$OS_NAME" != "linux" ]; then
    echo "See $DOCS_URL for Azure Functions Core Tools installation"
    exit 1
  fi
fi

########################
# Log in to azure and set up secrets.
# Ensure clean secrets.
rm -f secrets-export.sh
bash ./login.sh
source ./secrets-export.sh

########################
# Start an Atlas Cluster

# Get the utility functions
. ../../atlas/atlas-utils.sh

# Generate a random cluster name.
# See: https://docs.atlas.mongodb.com/reference/atlas-limits/#label-limits
DEPLOYMENT_NAME="$RANDOM-DRIVERGCP"
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

# Ensure Azure Functions Core Tools is installed.
URL=https://github.com/Azure/azure-functions-core-tools/releases/download/4.0.5907/Azure.Functions.Cli.linux-x64.4.0.5907.zip
if ! command -v func &> /dev/null; then
  curl -L -o /tmp/azure-functions-cli.zip $URL
  unzip -q -d /tmp/azure-functions-cli /tmp/azure-functions-cli.zip
  pushd /tmp/azure-functions-cli
  mkdir -p $DRIVERS_TOOLS/.bin
  chmod +x func
  chmod +x gozip
  mv func $DRIVERS_TOOLS/.bin
  mv gozip $DRIVERS_TOOLS/.bin
  popd
fi

########################
# Wait for the Atlas Cluster
export MONGODB_URI=$(check_deployment)
echo "export MONGODB_URI=$MONGODB_URI" >> ./secrets-export.sh

popd
