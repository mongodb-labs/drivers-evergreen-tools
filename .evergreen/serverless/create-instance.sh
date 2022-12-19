#!/usr/bin/env bash

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

if [ -z "$SERVERLESS_DRIVERS_GROUP" ]; then
    echo "Drivers Atlas group must be provided via SERVERLESS_DRIVERS_GROUP environment variable"
    exit 1
fi

if [ -z "$SERVERLESS_API_PRIVATE_KEY" ]; then
    echo "Atlas API private key must be provided via SERVERLESS_API_PRIVATE_KEY environment variable"
    exit 1
fi

if [ -z "$SERVERLESS_API_PUBLIC_KEY" ]; then
    echo "Atlas API public key must be provided via SERVERLESS_API_PUBLIC_KEY environment variable"
    exit 1
fi

# Historically, this script accepted LOADBALANCED=ON to opt in to testing load
# balanced serverless instances. Since all serverless instances now use a load
# balancer, prohibit opting out (i.e. defining LOADBALANCED != ON).
if [ -n "$LOADBALANCED" -a "$LOADBALANCED" != "ON" ]; then
    echo "Cannot opt out of testing load balanced serverless instances"
    exit 1
fi

# Generate a random instance name if one was not provided.
# See: https://docs.atlas.mongodb.com/reference/atlas-limits/#label-limits
if [ -z "$SERVERLESS_INSTANCE_NAME" ]; then
    SERVERLESS_INSTANCE_NAME="$RANDOM-DRIVERTEST"
fi

# Ensure that a Python binary is available for JSON decoding
# shellcheck source=.evergreen/find-python3.sh
. ../find-python3.sh || return

PYTHON_BINARY="$(find_python3)"

if [ -z "$PYTHON_BINARY" ]; then
    echo "Failed to find Python3 binary"
    exit 1
fi

echo "Creating new serverless instance \"$SERVERLESS_INSTANCE_NAME\"..."

# See: https://www.mongodb.com/docs/atlas/reference/api/serverless/create-one-serverless-instance/
API_BASE_URL="https://account-dev.mongodb.com/api/atlas/v1.0/groups/$SERVERLESS_DRIVERS_GROUP"

# Note: backingProviderName and regionName below should correspond to the
# multi-tenant MongoDB (MTM) associated with $SERVERLESS_DRIVERS_GROUP.
curl \
  -u "$SERVERLESS_API_PUBLIC_KEY:$SERVERLESS_API_PRIVATE_KEY" \
  --silent \
  --show-error \
  -X POST \
  --digest \
  --header "Accept: application/json" \
  --header "Content-Type: application/json" \
  "$API_BASE_URL/serverless?pretty=true" \
  --data @- << EOF
{
  "name" : "$SERVERLESS_INSTANCE_NAME",
  "providerSettings" : {
    "providerName": "SERVERLESS",
    "backingProviderName": "AWS",
    "instanceSizeName" : "SERVERLESS_V2",
    "regionName" : "US_EAST_2"
  }
}
EOF

echo ""

SECONDS=0
DIR=$(dirname $0)

while [ true ]; do
    API_RESPONSE=`SERVERLESS_INSTANCE_NAME=$SERVERLESS_INSTANCE_NAME bash $DIR/get-instance.sh`
    STATE_NAME=`echo $API_RESPONSE | $PYTHON_BINARY -c "import sys, json; print(json.load(sys.stdin)['stateName'])" | tr -d '\r\n'`
    SERVERLESS_MONGODB_VERSION=`echo $API_RESPONSE | $PYTHON_BINARY -c "import sys, json; print(json.load(sys.stdin)['mongoDBVersion'])" | tr -d '\r\n'`

    if [ "$STATE_NAME" = "IDLE" ]; then
        duration="$SECONDS"
        echo "Setup done! ($(($duration / 60))m $(($duration % 60))s elapsed)"

        SERVERLESS_URI=`echo $API_RESPONSE | $PYTHON_BINARY -c "import sys, json; print(json.load(sys.stdin)['connectionStrings']['standardSrv'])" | tr -d '\r\n'`

        SERVERLESS_URI=$SERVERLESS_URI \
        SERVERLESS_INSTANCE_NAME=$SERVERLESS_INSTANCE_NAME \
        cat << EOF > serverless-expansion.yml
SERVERLESS_URI: "$SERVERLESS_URI"
SERVERLESS_INSTANCE_NAME: "$SERVERLESS_INSTANCE_NAME"

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

        if [ "$SERVERLESS_SKIP_CRYPT" != "OFF" ]; then
          # Download binaries and crypt_shared
          MONGODB_VERSION=rapid sh $DIR/download-crypt.sh
        fi

        exit 0
    else
        echo "Setup still in progress, status=$STATE_NAME, sleeping for 1 minute..."
        sleep 60
    fi
done
