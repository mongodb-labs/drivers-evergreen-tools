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
DEPLOYMENT_NAME="$RANDOM-DRIVER-K8S"
echo "export CLUSTER_NAME=$DEPLOYMENT_NAME" >> "$DRIVERS_TOOLS/.evergreen/atlas/secrets-export.sh"

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

########################
# Wait for the Atlas Cluster
URI=$(check_deployment)

cat <<EOF >> "secrets-export.sh"
export MONGODB_URI="$URI"
export MONGODB_URI_SINGLE="$URI/?authMechanism=MONGODB-OIDC&authMechanismProperties=ENVIRONMENT:k8s"
export OIDC_ADMIN_USER=$OIDC_ATLAS_USER
export OIDC_ADMIN_PWD=$OIDC_ATLAS_PASSWORD
EOF

popd
