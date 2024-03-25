#!/usr/bin/env bash
set -eu

# Explanation of required environment variables:
#
# CLUSTER_PREFIX: The prefix for the cluster name, (e.g. dbx-python)

# Explanation of generated variables:
#
# CLUSTER_NAME: The name of the created cluster.
# ATLAS_BASE_URL: Where the Atlas API root resides.

# The base Atlas API url. We use the API directly as the CLI does not yet
# support testing cluster outages.
DEFAULT_URL="https://cloud.mongodb.com/api/atlas/v1.0"
ATLAS_BASE_URL="${DRIVERS_ATLAS_BASE_URL:-$DEFAULT_URL}"

# Create a unique atlas project name.
suffix=$(node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex').slice(0,16))")
CLUSTER_NAME="${CLUSTER_PREFIX}-${suffix}"
