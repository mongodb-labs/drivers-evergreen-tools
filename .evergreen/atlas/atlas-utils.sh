#!/usr/bin/env bash
set -eu


# Create an Atlas M10 deployment - this returns immediately so we'll need to poll until
# the deployment is created.
create_deployment ()
{
  VARLIST=(
  ATLAS_PUBLIC_API_KEY
  ATLAS_PRIVATE_API_KEY
  DEPLOYMENT_DATA
  ATLAS_GROUP_ID
  )

  # Ensure that all variables required to run the test are set, otherwise throw
  # an error.
  for VARNAME in ${VARLIST[*]}; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
  done

  ATLAS_BASE_URL=${ATLAS_BASE_URL:-"https://account-dev.mongodb.com/api/atlas/v1.0"}
  TYPE=${DEPLOYMENT_TYPE:-"clusters"}
  echo "Creating new Atlas Deployment in Group $ATLAS_GROUP_ID..."
  curl -sS -L \
    --digest -u "${ATLAS_PUBLIC_API_KEY}:${ATLAS_PRIVATE_API_KEY}" \
    -d "${DEPLOYMENT_DATA}" \
    -H 'Content-Type: application/json' \
    -X POST \
    "${ATLAS_BASE_URL}/groups/${ATLAS_GROUP_ID}/${TYPE}?pretty=true" \
    -w "%{http_code}" \
    -o "resp.txt"

  resp=$(cat resp.txt)
  if [[ "$resp" != "201" ]]; then
    echo "Exiting due to response code $resp != 201"
    exit 1
  fi
  echo "Creating new Atlas Deployment in Group $ATLAS_GROUP_ID... done."
}

# Check if deployment has a srv address, and assume once it does, it can be used.
check_deployment ()
{
  VARLIST=(
  ATLAS_PUBLIC_API_KEY
  ATLAS_PRIVATE_API_KEY
  ATLAS_GROUP_ID
  DEPLOYMENT_NAME
  )

  # Ensure that all variables required to run the test are set, otherwise throw
  # an error.
  for VARNAME in ${VARLIST[*]}; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
  done

  count=0
  SRV_ADDRESS="null"

  ATLAS_BASE_URL=${ATLAS_BASE_URL:-"https://account-dev.mongodb.com/api/atlas/v1.0"}
  TYPE=${DEPLOYMENT_TYPE:-"clusters"}
  if [ $TYPE = "serverless" ]; then
      match_str=".connectionStrings.standardSrv"
  else
      match_str=".srvAddress"
  fi

  # Don't try longer than 20 minutes.
  echo "" 1>&2
  echo "Waiting for Deployment $DEPLOYMENT_NAME in Group $ATLAS_GROUP_ID..." 1>&2
  while [ $SRV_ADDRESS = "null" ] && [ $count -le 80 ]; do
    echo "Checking every 15 seconds for deployment to be created..." 1>&2
    # Poll every 15 seconds to check the deployment creation.
    sleep 15
    curl -sS -L \
      --digest -u "${ATLAS_PUBLIC_API_KEY}:${ATLAS_PRIVATE_API_KEY}" \
      -X GET \
      "${ATLAS_BASE_URL}/groups/${ATLAS_GROUP_ID}/${TYPE}/${DEPLOYMENT_NAME}"
      -o resp.txt
    SRV_ADDRESS=$(cat resp.txt | jq -r ${match_str})
    count=$(( $count + 1 ))
  done

  if [ $SRV_ADDRESS = "null" ]; then
    echo "No deployment could be created in the 20 minute timeframe or error occurred." 1>&2
    exit 1
  else
    # Return the MONGODB_URI
    echo $SRV_ADDRESS
  fi
  echo "Waiting for Deployment $DEPLOYMENT_NAME in Group $ATLAS_GROUP_ID... done." 1>&2
}
