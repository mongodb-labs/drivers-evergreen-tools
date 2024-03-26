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
  echo "Creating new Atlas Deployment..."
  resp=$(curl \
    --digest -u "${ATLAS_PUBLIC_API_KEY}:${ATLAS_PRIVATE_API_KEY}" \
    -d "${DEPLOYMENT_DATA}" \
    -H 'Content-Type: application/json' \
    -X POST \
    "${ATLAS_BASE_URL}/groups/${ATLAS_GROUP_ID}/${TYPE}?pretty=true" \
    -o /dev/stderr  \
    -w "%{http_code}")
  if [[ "$resp" != "201" ]]; then
    echo "Exiting due to response code $resp != 201"
    exit 1
  fi
  echo "Creating new Atlas Deployment... done."
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

  # Don't try longer than 20 minutes.
  while [ $SRV_ADDRESS = "null" ] && [ $count -le 80 ]; do
    echo "Checking every 15 seconds for deployment to be created..." 1>&2
    # Poll every 15 seconds to check the deployment creation.
    sleep 15
    SRV_ADDRESS=$(curl \
      --digest -u "${ATLAS_PUBLIC_API_KEY}:${ATLAS_PRIVATE_API_KEY}" \
      -X GET \
      -o /dev/stderr  \
      "${ATLAS_BASE_URL}/groups/${ATLAS_GROUP_ID}/${DEPLOYMENT_TYPE}/${DEPLOYMENT_NAME}" \
      | jq -r '.srvAddress'
    );
    count=$(( $count + 1 ))
  done

  if [ $SRV_ADDRESS = "null" ]; then
    echo "No deployment could be created in the 20 minute timeframe or error occurred."
    exit 1
  else
    # Return the MONGODB_URI
    echo $SRV_ADDRESS | grep -Eo "[^(\/\/)]*$" | cat
  fi
}
