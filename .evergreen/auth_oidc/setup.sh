#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Get the secrets
rm -f secrets-export.sh
. ./setup-secrets.sh

# Get the tokens.
bash ./oidc_get_tokens.sh

if [ "$(uname -s)" = "Linux" ]; then
    # On Linux, we start a local server so we can have better control of the idp configuration.
    . ./activate-authoidcvenv.sh
    python oidc_write_orchestration.py
    TOPOLOGY=replica_set ORCHESTRATION_FILE=auth-oidc.json bash ../run-orchestration.sh
    URI="mongodb://127.0.0.1:27017/?directConnection=true"
    $MONGODB_BINARIES/mongosh -f ./setup_oidc.js "$URI&serverSelectionTimeoutMS=10000"
    cat <<EOF >> "secrets-export.sh"
export MONGODB_URI="$URI"
export MONGODB_URI_SINGLE="$URI&authMechanism=MONGODB-OIDC"
export MONGODB_URI_MULTI="mongodb://127.0.0.1:27018/?directConnection=true&authMechanism=MONGODB-OIDC"
export OIDC_ADMIN_USER=bob
export OIDC_ADMIN_PWD=pwd123
export OIDC_IS_LOCAL=1

EOF
else
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

  URI=$(check_deployment)
  cat <<EOF >> "secrets-export.sh"
export MONGODB_URI="$URI"
export MONGODB_URI_SINGLE="$URI/?authMechanism=MONGODB-OIDC"
export OIDC_ADMIN_USER=$OIDC_ATLAS_USER
export OIDC_ADMIN_PWD=$OIDC_ATLAS_PASSWORD
EOF
fi

popd
