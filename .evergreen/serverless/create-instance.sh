#!/bin/bash

set -o errexit

echo "in create instance"

if [ -z "$1" ]; then
    echo "Instance name must be provided as a command line argument"
    exit 1
fi

echo "instance name provided"

if [ -z "$SERVERLESS_DRIVERS_GROUP" ]; then
    echo "Drivers Atlas group must be provided via SERVERLESS_DRIVERS_GROUP environment variable"
    exit 1
fi

echo "group provided"

if [ -z "$SERVERLESS_API_PRIVATE_KEY" ]; then
    echo "Atlas API private key must be provided via SERVERLESS_API_PRIVATE_KEY environment variable"
    exit 1
fi

echo "private key provideD"

if [ -z "$SERVERLESS_API_PUBLIC_KEY" ]; then
    echo "Atlas API public key must be provided via SERVERLESS_API_PUBLIC_KEY environment variable"
    exit 1
fi

echo "public key provided"

API_BASE_URL="https://account-dev.mongodb.com/api/atlas/v1.0/groups/$SERVERLESS_DRIVERS_GROUP"

curl \
  -i \
  -u "$SERVERLESS_API_PUBLIC_KEY:$SERVERLESS_API_PRIVATE_KEY" \
  -X POST \
  --digest \
  --header "Accept: application/json" \
  --header "Content-Type: application/json" \
  "$API_BASE_URL/serverless/instances?pretty=true" \
  --data "
    {
      \"name\" : \"${1}\",
      \"providerSettings\" : {
        \"providerName\": \"SERVERLESS\",
        \"backingProviderName\": \"AWS\",
        \"instanceSizeName\" : \"SERVERLESS_V1\",
        \"regionName\" : \"US_EAST_1\"
      }
    }"

echo ""

echo "curl done"

SECONDS=0
while [ true ]; do
    echo "checking status of instance..."
    API_RESPONSE=`bash get-instance.sh $1`
    STATE_NAME=`echo $API_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['stateName'])"`

    if [ ${STATE_NAME} == "IDLE" ]; then
        duration="$SECONDS"
        echo "setup done! ($(($duration / 60))m $(($duration % 60))s elapsed)"
        SRV_ADDRESS=$(echo $API_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['srvAddress'])")
        echo "MONGODB_SRV_URI=$SRV_ADDRESS"
        STANDARD_ADDRESS=$(echo $API_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['mongoURI'])")
        echo "MONGODB_URI=$STANDARD_ADDRESS"
        cat <<EOF > serverless-expansion.yml
MONGODB_URI: "$STANDARD_ADDRESS"
MONGODB_SRV_URI: "$SRV_ADDRESS"
SSL: ssl
AUTH: auth
TOPOLOGY: sharded_cluster
SERVERLESS: serverless
MONGODB_API_VERSION: 1
EOF
        exit 0
    else
        echo "setup still in progress, status=$STATE_NAME, sleeping for 1 minute..."
        sleep 60
    fi
done
