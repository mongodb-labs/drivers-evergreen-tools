#!/bin/bash

set -o errexit
set +o xtrace # disable xtrace to ensure credentials aren't leaked

if [ -z "$PROJECT" ]; then
    echo "Project name must be provided via PROJECT environment variable"
    exit 1
fi
INSTANCE_NAME="$RANDOM-$PROJECT"

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

echo "creating new serverless instance \"${INSTANCE_NAME}\"..."

DIR=$(dirname $0)
API_BASE_URL="https://account-dev.mongodb.com/api/atlas/v1.0/groups/$SERVERLESS_DRIVERS_GROUP"

curl \
  -u "$SERVERLESS_API_PUBLIC_KEY:$SERVERLESS_API_PRIVATE_KEY" \
  --silent \
  --show-error \
  -X POST \
  --digest \
  --header "Accept: application/json" \
  --header "Content-Type: application/json" \
  "$API_BASE_URL/serverless?pretty=true" \
  --data "
    {
      \"name\" : \"${INSTANCE_NAME}\",
      \"providerSettings\" : {
        \"providerName\": \"SERVERLESS\",
        \"backingProviderName\": \"AWS\",
        \"instanceSizeName\" : \"SERVERLESS_V2\",
        \"regionName\" : \"US_EAST_1\"
      }
    }"

echo ""

if [ "Windows_NT" = "$OS" ]; then
  PYTHON_BINARY=C:/python/Python38/python.exe
else
  PYTHON_BINARY=python3
fi

SECONDS=0
while [ true ]; do
    API_RESPONSE=`SERVERLESS_INSTANCE_NAME=$INSTANCE_NAME bash $DIR/get-instance.sh`
    STATE_NAME=`echo $API_RESPONSE | $PYTHON_BINARY -c "import sys, json; print(json.load(sys.stdin)['stateName'])" | tr -d '\r\n'`

    if [ "$STATE_NAME" = "IDLE" ]; then
        duration="$SECONDS"
        echo "setup done! ($(($duration / 60))m $(($duration % 60))s elapsed)"
        echo "SERVERLESS_INSTANCE_NAME=\"$INSTANCE_NAME\""
        SRV_ADDRESS=$(echo $API_RESPONSE | $PYTHON_BINARY -c "import sys, json; print(json.load(sys.stdin)['srvAddress'])" | tr -d '\r\n')
        echo "MONGODB_SRV_URI=\"$SRV_ADDRESS\""
        STANDARD_ADDRESS=$(echo $API_RESPONSE | $PYTHON_BINARY -c "import sys, json; print(json.load(sys.stdin)['mongoURI'])" | tr -d '\r\n')
        echo "MONGODB_URI=\"$STANDARD_ADDRESS/?loadBalanced=true\""
        MULTI_ATLASPROXY_SERVERLESS_URI="$SRV_ADDRESS"
        echo "MULTI_ATLASPROXY_SERVERLESS_URI=\"$MULTI_ATLASPROXY_SERVERLESS_URI\""
        SINGLE_ATLASPROXY_SERVERLESS_URI=$(echo $STANDARD_ADDRESS | $PYTHON_BINARY -c "import sys; uri=sys.stdin.read(); print (uri[0:uri.find(',')] + '/?loadBalanced=true&tls=true')" | tr -d '\r\n')
        echo "SINGLE_ATLASPROXY_SERVERLESS_URI=\"$SINGLE_ATLASPROXY_SERVERLESS_URI\""

        cat <<EOF > serverless-expansion.yml
MONGODB_URI: "$STANDARD_ADDRESS"
MONGODB_SRV_URI: "$SRV_ADDRESS"
SERVERLESS_INSTANCE_NAME: "$INSTANCE_NAME"
SSL: ssl
AUTH: auth
TOPOLOGY: sharded_cluster
SERVERLESS: serverless
MULTI_ATLASPROXY_SERVERLESS_URI: "$MULTI_ATLASPROXY_SERVERLESS_URI"
SINGLE_ATLASPROXY_SERVERLESS_URI: "$SINGLE_ATLASPROXY_SERVERLESS_URI"
EOF
        exit 0
    else
        echo "setup still in progress, status=$STATE_NAME, sleeping for 1 minute..."
        sleep 60
    fi
done
