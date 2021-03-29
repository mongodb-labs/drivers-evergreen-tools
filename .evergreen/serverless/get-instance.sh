#!/bin/bash

if [ -z "$1" ]; then
    echo "Instance name must be provided as a command line argument"
    exit 1
fi

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

API_BASE_URL="https://account-dev.mongodb.com/api/atlas/v1.0/groups/$SERVERLESS_DRIVERS_GROUP"

curl \
  -s \
  -u "$SERVERLESS_API_PUBLIC_KEY:$SERVERLESS_API_PRIVATE_KEY" \
  -X GET \
  --digest \
  --header "Accept: application/json" \
  "$API_BASE_URL/serverless/instances/$1?pretty=true" \

echo ""
