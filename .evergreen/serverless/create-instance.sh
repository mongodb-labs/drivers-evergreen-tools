#!/bin/bash

set -o errexit
set +o xtrace # disable xtrace to ensure credentials aren't leaked

if [ -z "$PROJECT" ]; then
    echo "Project name must be provided via PROJECT environment variable"
    exit 1
fi
INSTANCE_NAME="$RANDOM-$PROJECT"

# Set the LOADBALANCED environment variable to "ON" to opt-in to
# testing load balanced serverless instances.
if [ "$LOADBALANCED" = "ON" ]; then
    BACKING_PROVIDER_NAME="AWS"
    INSTANCE_REGION_NAME="US_EAST_1"
else
    BACKING_PROVIDER_NAME="GCP"
    INSTANCE_REGION_NAME="CENTRAL_US"
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
        \"backingProviderName\": \"$BACKING_PROVIDER_NAME\",
        \"instanceSizeName\" : \"SERVERLESS_V2\",
        \"regionName\" : \"$INSTANCE_REGION_NAME\"
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

        API_RESPONSE=$API_RESPONSE \
        INSTANCE_NAME=$INSTANCE_NAME \
        LOADBALANCED=$LOADBALANCED \
        $PYTHON_BINARY - << EOF | tee serverless-expansion.yml
import json
import sys
import os

def upsert_option(uri, name, value):
    # Add the URI option <name>=<value> to the URI if it is not already present.
    if "?" not in uri:
        if uri.endswith("/"):
            return uri + "?" + name + "=" + value
        else:
            return uri + "/?" + name + "=" + value

    option_string = uri[uri.find("?")+1:]
    options = option_string.split("&")
    option_names = [option.split("=")[0] for option in options]
    if name in option_names:
        return uri
    else:
        return uri + "&" + name + "=" + value

def select_last_host(uri):
    return "mongodb://" + uri[uri.rfind(",")+1:]

api_response = json.loads(os.environ["API_RESPONSE"])

# The srvAddress response field is an SRV URI pointing to the load balancer. A
# corresponding TXT record includes the loadBalanced=true URI option. This will
# be used for MULTI_ATLASPROXY_SERVERLESS_URI.
mongodb_srv_uri = api_response['srvAddress']
multi_atlasproxy_serverless_uri = mongodb_srv_uri

# The mongoURI response field reports the serverless instance(s) behind the load
# balancer. This script will reduce it to a single host and append necessary URI
# options to construct SINGLE_ATLASPROXY_SERVERLESS_URI, which is necessary for
# testing fail points (much like SINGLE_LB_MONGOS_URI).
mongodb_uri = api_response['mongoURI']
single_atlasproxy_serverless_uri = select_last_host(mongodb_uri)
single_atlasproxy_serverless_uri = upsert_option(single_atlasproxy_serverless_uri, "loadBalanced", "true")
single_atlasproxy_serverless_uri = upsert_option(single_atlasproxy_serverless_uri, "tls", "true")

if os.environ.get("LOADBALANCED") == "ON":
    mongodb_uri = upsert_option(mongodb_uri, "loadBalanced", "true")

print (f'MONGODB_URI: "{mongodb_uri}"')
print (f'MONGODB_SRV_URI: "{mongodb_srv_uri}"')
print (f'SERVERLESS_INSTANCE_NAME: "{os.environ["INSTANCE_NAME"]}"')
print (f'SSL: ssl')
print (f'AUTH: auth')
print (f'TOPOLOGY: sharded_cluster')
print (f'SERVERLESS: serverless')
print (f'MULTI_ATLASPROXY_SERVERLESS_URI: "{multi_atlasproxy_serverless_uri}"')
print (f'SINGLE_ATLASPROXY_SERVERLESS_URI: "{single_atlasproxy_serverless_uri}"')
EOF
        exit 0
    else
        echo "setup still in progress, status=$STATE_NAME, sleeping for 1 minute..."
        sleep 60
    fi
done
