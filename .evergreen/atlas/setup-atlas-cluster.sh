#!/usr/bin/env bash
set -eu

# Explanation of required environment variables:
#
# DRIVERS_ATLAS_PUBLIC_API_KEY: The public Atlas key for the drivers org.
# DRIVERS_ATLAS_PRIVATE_API_KEY: The private Atlas key for the drivers org.
# DRIVERS_ATLAS_GROUP_ID: The id of the individual projects under the drivers org, per language.
# DRIVERS_ATLAS_USER: The user for the cluster.
# DRIVERS_ATLAS_PASSWORD: The password for the user.
# CLUSTER_PREFIX: The prefix for the cluster name, (e.g. dbx-python)
# MONGODB_VERSION: The major version of the cluster to deploy.  Defaults to 6.0.

# Explanation of generated variables:
#
# MONGODB_URI: The URI for the created Atlas cluster during this script.
# CLUSTER_NAME: Uses the stack name plus the current commit sha to create a unique cluster and function.
# CREATE_CLUSTER_JSON: The JSON used to create a cluster via the Atlas API.
# ATLAS_BASE_URL: Where the Atlas API root resides.

# Set up the common variables.
CURRENT_DIR=$(pwd)
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Load the secrets file if it exists.
if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi

# Attempt to handle the secrets automatically if env vars are not set.
if [ -z "${DRIVERS_ATLAS_PUBLIC_API_KEY:-}" ]; then
  . ./setup-secrets.sh "$@"
fi

# Backwards compatibility: map old names to new names.
if [ -n "${LAMBDA_STACK_NAME:-}" ]; then
  # shellcheck disable=SC2034
  CLUSTER_PREFIX=$LAMBDA_STACK_NAME
fi
if [ -n "${DRIVERS_ATLAS_LAMBDA_USER:-}" ]; then
  DRIVERS_ATLAS_USER=$DRIVERS_ATLAS_LAMBDA_USER
fi
if [ -n "${DRIVERS_ATLAS_LAMBDA_PASSWORD:-}" ]; then
  DRIVERS_ATLAS_PASSWORD=$DRIVERS_ATLAS_LAMBDA_PASSWORD
fi

VARLIST=(
DRIVERS_ATLAS_PUBLIC_API_KEY
DRIVERS_ATLAS_PRIVATE_API_KEY
DRIVERS_ATLAS_GROUP_ID
DRIVERS_ATLAS_USER
DRIVERS_ATLAS_PASSWORD
CLUSTER_PREFIX
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
[[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Set up the cluster variables.
. $SCRIPT_DIR/setup-variables.sh

# Get the utility functions
. $SCRIPT_DIR/atlas-utils.sh

# The cluster server version.
export VERSION="${MONGODB_VERSION:-6.0}"

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
  "mongoDBMajorVersion" : "${VERSION}",
  "name" : "${CLUSTER_NAME}",
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

export ATLAS_PUBLIC_API_KEY=$DRIVERS_ATLAS_PUBLIC_API_KEY
export ATLAS_PRIVATE_API_KEY=$DRIVERS_ATLAS_PRIVATE_API_KEY
export ATLAS_GROUP_ID=$DRIVERS_ATLAS_GROUP_ID
export DEPLOYMENT_NAME=$CLUSTER_NAME

create_deployment

# Add variables to secrets file so we can shut down the cluster if needed.
echo "export ATLAS_BASE_URL=$ATLAS_BASE_URL" >> ./secrets-export.sh
echo "export CLUSTER_NAME=$DEPLOYMENT_NAME" >> ./secrets-export.sh

RAW_URI=$(check_deployment)
URI=$(echo $RAW_URI | grep -Eo "[^(\/\/)]*$" | cat)
MONGODB_URI="mongodb+srv://${DRIVERS_ATLAS_USER}:${DRIVERS_ATLAS_PASSWORD}@${URI}"

# Put the MONGODB_URI in an expansions yml and secrets file.
echo 'MONGODB_URI: "'$MONGODB_URI'"' > $CURRENT_DIR/atlas-expansion.yml
echo "export MONGODB_URI=$MONGODB_URI" >> ./secrets-export.sh
popd
