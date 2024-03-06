#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail

# Explanation of required environment variables:
#
# DRIVERS_ATLAS_PUBLIC_API_KEY: The public Atlas key for the drivers org.
# DRIVERS_ATLAS_PRIVATE_API_KEY: The private Atlas key for the drivers org.
# DRIVERS_ATLAS_GROUP_ID: The id of the individual projects under the drivers org, per language.
# DRIVERS_ATLAS_LAMBDA_USER: The user for the lambda cluster.
# DRIVERS_ATLAS_LAMBDA_PASSWORD: The password for the user.
# LAMBDA_STACK_NAME: The name of the stack on lambda "dbx-<language>-lambda"
# MONGODB_VERSION: The major version of the cluster to deploy.  Defaults to 6.0.

# Explanation of generated variables:
#
# MONGODB_URI: The URI for the created Atlas cluster during this script.
# FUNCTION_NAME: Uses the stack name plus the current commit sha to create a unique cluster and function.
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
if [ -z "$DRIVERS_ATLAS_PUBLIC_API_KEY" ]; then
  . ../secrets_handling/setup-secrets.sh drivers/atlas
fi

VARLIST=(
DRIVERS_ATLAS_PUBLIC_API_KEY
DRIVERS_ATLAS_PRIVATE_API_KEY
DRIVERS_ATLAS_GROUP_ID
DRIVERS_ATLAS_LAMBDA_USER
DRIVERS_ATLAS_LAMBDA_PASSWORD
LAMBDA_STACK_NAME
task_id
execution
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in ${VARLIST[*]}; do
[[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Set up the cluster variables.
. $SCRIPT_DIR/setup-variables.sh

# The cluster server version.
VERSION="${MONGODB_VERSION:-6.0}"

# Set the create cluster configuration.
CREATE_CLUSTER_JSON=$(cat <<EOF
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
  "name" : "${FUNCTION_NAME}",
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

# Create an Atlas M10 cluster - this returns immediately so we'll need to poll until
# the cluster is created.
create_cluster ()
{
  echo "Creating new Atlas Cluster..."
  resp=$(curl \
    --digest -u "${DRIVERS_ATLAS_PUBLIC_API_KEY}:${DRIVERS_ATLAS_PRIVATE_API_KEY}" \
    -d "${CREATE_CLUSTER_JSON}" \
    -H 'Content-Type: application/json' \
    -X POST \
    "${ATLAS_BASE_URL}/groups/${DRIVERS_ATLAS_GROUP_ID}/clusters?pretty=true" \
    -o /dev/stderr  \
    -w "%{http_code}")
  if [[ "$resp" -neq "200" ]]; then
    exit 1
  fi
  echo "Creating new Atlas Cluster... done."
}

# Check if cluster has a srv address, and assume once it does, it can be used.
check_cluster ()
{
  count=0
  SRV_ADDRESS="null"
  # Don't try longer than 20 minutes.
  while [ $SRV_ADDRESS = "null" ] && [ $count -le 80 ]; do
    echo "Checking every 15 seconds for cluster to be created..."
    # Poll every 15 seconds to check the cluster creation.
    sleep 15
    SRV_ADDRESS=$(curl \
      --digest -u "${DRIVERS_ATLAS_PUBLIC_API_KEY}:${DRIVERS_ATLAS_PRIVATE_API_KEY}" \
      -X GET \
      "${ATLAS_BASE_URL}/groups/${DRIVERS_ATLAS_GROUP_ID}/clusters/${FUNCTION_NAME}" \
      | jq -r '.srvAddress'
    );
    count=$(( $count + 1 ))
    echo $SRV_ADDRESS
  done

  if [ $SRV_ADDRESS = "null" ]; then
    echo "No cluster could be created in the 20 minute timeframe or error occurred."
    exit 1
  else
    echo "Setting MONGODB_URI in the environment to the new cluster."
    # else set the mongodb uri
    URI=$(echo $SRV_ADDRESS | grep -Eo "[^(\/\/)]*$" | cat)
    MONGODB_URI="mongodb+srv://${DRIVERS_ATLAS_LAMBDA_USER}:${DRIVERS_ATLAS_LAMBDA_PASSWORD}@${URI}"
    # Put the MONGODB_URI in an expansions yml and secrets file.
    echo 'MONGODB_URI: "'$MONGODB_URI'"' > $CURRENT_DIR/atlas-expansion.yml
    echo "export MONGODB_URI=$MONGODB_URI" >> ./secrets-export.sh
  fi
}

create_cluster

check_cluster

popd
