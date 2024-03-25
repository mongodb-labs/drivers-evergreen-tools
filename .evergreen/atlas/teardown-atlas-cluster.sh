#!/usr/bin/env bash
set -eu

# Explanation of required environment variables:
#
# DRIVERS_ATLAS_PUBLIC_API_KEY: The public Atlas key for the drivers org.
# DRIVERS_ATLAS_PRIVATE_API_KEY: The private Atlas key for the drivers org.
# DRIVERS_ATLAS_GROUP_ID: The id of the individual projects under the drivers org, per language.

VARLIST=(
DRIVERS_ATLAS_PUBLIC_API_KEY
DRIVERS_ATLAS_PRIVATE_API_KEY
DRIVERS_ATLAS_GROUP_ID
CLUSTER_NAME
)

# Set up the common variables.
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in ${VARLIST[*]}; do
[[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Delete the cluster.
echo "Deleting Atlas Cluster..."
curl \
  --digest -u ${DRIVERS_ATLAS_PUBLIC_API_KEY}:${DRIVERS_ATLAS_PRIVATE_API_KEY} \
  -X DELETE \
  "${ATLAS_BASE_URL}/groups/${DRIVERS_ATLAS_GROUP_ID}/clusters/${CLUSTER_NAME}?pretty=true"

popd
