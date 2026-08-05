#!/usr/bin/env bash
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.

echo "Starting MongoDB server ... begin"
DRIVERS_TOOLS=$(pwd)/drivers-evergreen-tools
if [ -f drivers-evergreen-tools.tgz ]; then
  # create-and-setup-vm.sh shipped the host's checkout, so this VM runs the same
  # revision that provisioned it.
  mkdir -p "$DRIVERS_TOOLS"
  tar xzf drivers-evergreen-tools.tgz -C "$DRIVERS_TOOLS"
else
  # No archive: the host could not build one. Cloning the default branch may not
  # match the script that provisioned this VM.
  echo "WARNING: no drivers-evergreen-tools archive; cloning the default branch instead."
  git clone https://github.com/mongodb-labs/drivers-evergreen-tools
fi
export DRIVERS_TOOLS
export MONGO_ORCHESTRATION_HOME="$DRIVERS_TOOLS/.evergreen/orchestration"
export MONGODB_BINARIES="$DRIVERS_TOOLS/mongodb/bin"
echo "{ \"releases\": { \"default\": \"$MONGODB_BINARIES\" }}" > "$MONGO_ORCHESTRATION_HOME"/orchestration.config
# Use run-orchestration with defaults.
bash "${DRIVERS_TOOLS}"/.evergreen/run-orchestration.sh
echo "Starting MongoDB server ... end"
