#!/usr/bin/env bash

if [ -z "$BASH" ]; then
  echo "create-instance.sh must be run in a Bash shell!" 1>&2
  exit 1
fi

set -o errexit
set +o xtrace # Disable xtrace to ensure credentials aren't leaked

# Supported environment variables:
#
#   SERVERLESS_INSTANCE_NAME    Optional. Serverless instance to create (defaults to a random name).
#   SERVERLESS_DRIVERS_GROUP    Required. Atlas group for drivers testing.
#   SERVERLESS_API_PUBLIC_KEY   Required. Public key for Atlas API request.
#   SERVERLESS_API_PRIVATE_KEY  Required. Private key for Atlas API request.
#   SERVERLESS_SKIP_CRYPT       Optional. If set, skips installing mongocryptd and crypt_shared (defaults to "ON")
#
# On success, this script will output serverless-expansion.yml with the
# following expansions:
#
#   SERVERLESS_URI            SRV connection string for newly created instance
#   SERVERLESS_INSTANCE_NAME  Name of newly created instance (required for "get" and "delete" scripts)

CURRENT_DIR=$(pwd)
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Load the secrets file if it exists.
if [ -f "./secrets-export.sh" ]; then
  source "./secrets-export.sh"
fi

# Attempt to handle the secrets automatically if env vars are not set.
if [ -z "$SERVERLESS_DRIVERS_GROUP" ]; then
    . ./setup-secrets.sh ${VAULT_NAME:-}
  source ./secrets-export.sh
fi

VARLIST=(
SERVERLESS_DRIVERS_GROUP
SERVERLESS_API_PRIVATE_KEY
SERVERLESS_API_PUBLIC_KEY
SERVERLESS_DRIVERS_GROUP
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in ${VARLIST[*]}; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Historically, this script accepted LOADBALANCED=ON to opt in to testing load
# balanced serverless instances. Since all serverless instances now use a load
# balancer, prohibit opting out (i.e. defining LOADBALANCED != ON).
if [ -n "${LOADBALANCED:-}" -a "${LOADBALANCED:-}" != "ON" ]; then
    echo "Cannot opt out of testing load balanced serverless instances"
    exit 1
fi

# Generate a random instance name if one was not provided.
# See: https://docs.atlas.mongodb.com/reference/atlas-limits/#label-limits
if [ -z "${SERVERLESS_INSTANCE_NAME:-}" ]; then
    SERVERLESS_INSTANCE_NAME="$RANDOM-DRIVERTEST"
fi

SERVERLESS_REGION="${SERVERLESS_REGION:-US_EAST_2}"

echo "Creating new serverless instance \"$SERVERLESS_INSTANCE_NAME\"..."

export ATLAS_PUBLIC_API_KEY=$SERVERLESS_API_PUBLIC_KEY
export ATLAS_PRIVATE_API_KEY=$SERVERLESS_API_PRIVATE_KEY
export ATLAS_GROUP_ID=$SERVERLESS_DRIVERS_GROUP
export DEPLOYMENT_NAME=$SERVERLESS_INSTANCE_NAME
export DEPLOYMENT_TYPE=serverless

# Note: backingProviderName and regionName below should correspond to the
# multi-tenant MongoDB (MTM) associated with $SERVERLESS_DRIVERS_GROUP.
export DEPLOYMENT_DATA=$(cat <<EOF
{
  "name" : "$SERVERLESS_INSTANCE_NAME",
  "providerSettings" : {
    "providerName": "SERVERLESS",
    "backingProviderName": "AWS",
    "instanceSizeName" : "SERVERLESS_V2",
    "regionName" : "$SERVERLESS_REGION"
  }
}
EOF
)

# Get the utility functions
. $SCRIPT_DIR/../atlas/atlas-utils.sh

create_deployment

# Write the serverless instance name early for teardown in case there is an error.
echo "export SERVERLESS_INSTANCE_NAME=$SERVERLESS_INSTANCE_NAME" >> ./secrets-export.sh
echo "SERVERLESS_INSTANCE_NAME: \"$SERVERLESS_INSTANCE_NAME\"" > $CURRENT_DIR/serverless-expansion.yml

SERVERLESS_URI=$(check_deployment)

cat << EOF >> $CURRENT_DIR/serverless-expansion.yml
SERVERLESS_URI: "$SERVERLESS_URI"

# Define original variables for backwards compatibility
MONGODB_URI: "$SERVERLESS_URI"
MONGODB_SRV_URI: "$SERVERLESS_URI"
SSL: "ssl"
AUTH: "auth"
TOPOLOGY: "sharded_cluster"
SERVERLESS: "serverless"
SINGLE_ATLASPROXY_SERVERLESS_URI: "$SERVERLESS_URI"
MULTI_ATLASPROXY_SERVERLESS_URI: "$SERVERLESS_URI"
SERVERLESS_MONGODB_VERSION: "$SERVERLESS_MONGODB_VERSION"
EOF

# Add the uri to the secrets file.
if [ -f "./secrets-export.sh" ]; then
  echo "export SERVERLESS_URI=$SERVERLESS_URI" >> ./secrets-export.sh
fi

if [ "${SERVERLESS_SKIP_CRYPT:-}" != "OFF" ]; then
  # Download binaries and crypt_shared
  MONGODB_VERSION=rapid bash ./download-crypt.sh
fi

popd
