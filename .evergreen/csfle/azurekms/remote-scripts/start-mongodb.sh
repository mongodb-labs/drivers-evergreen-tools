#!/usr/bin/env bash
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.

echo "Starting MongoDB server ... begin"
git clone https://github.com/mongodb-labs/drivers-evergreen-tools
DRIVERS_TOOLS=$(pwd)/drivers-evergreen-tools
export DRIVERS_TOOLS
export MONGO_ORCHESTRATION_HOME="$DRIVERS_TOOLS/.evergreen/orchestration"
export MONGODB_BINARIES="$DRIVERS_TOOLS/mongodb/bin"
echo "{ \"releases\": { \"default\": \"$MONGODB_BINARIES\" }}" > "$MONGO_ORCHESTRATION_HOME"/orchestration.config
# Use run-orchestration with defaults.
bash "${DRIVERS_TOOLS}"/.evergreen/run-orchestration.sh
echo "Starting MongoDB server ... end"
