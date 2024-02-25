#!/usr/bin/env bash
# Handle proper teardown of all assets and services created by drivers-evergreen-tools.

set -o errexit  # Exit the script with error if any of the commands fail

# Set up the mongo orchestration config.
echo "{ \"releases\": { \"default\": \"$MONGODB_BINARIES\" }}" > $MONGO_ORCHESTRATION_HOME/orchestration.config

# Copy client certificate because symlinks do not work on Windows.
cp ${DRIVERS_TOOLS}/.evergreen/x509gen/client.pem ${MONGO_ORCHESTRATION_HOME}/lib/client.pem || true

# Create failing test result files.
echo '{"results": [{ "status": "FAIL", "test_file": "Build", "log_raw": "No test-results.json found was created"  } ]}' > ${PROJECT_DIRECTORY}/test-results.json

# Create a stub mongo-orchestration results file.
echo '{"results": [{ "status": "PASS", "test_file": "Build", "log_raw": "Stub file for mongo-orchestration results"  } ]}' > ${DRIVERS_TOOLS}/results.json

# Handle absolute paths.
for filename in $(find ${DRIVERS_TOOLS} -name \*.json); do
    perl -p -i -e "s|ABSOLUTE_PATH_REPLACEMENT_TOKEN|${DRIVERS_TOOLS}|g" $filename
done

# Install project dependencies.
if [ -f "$PROJECT_DIRECTORY/.evergreen/install-dependencies.sh" ]; then
    bash "$PROJECT_DIRECTORY/.evergreen/install-dependencies.sh"
fi

# Ensure there is at least one log file.
cat << EOF > ${DRIVERS_TOOLS}/.evergreen/test.log
PROJECT_DIRECTORY=$PROJECT_DIRECTORY
DRIVERS_TOOLS=$DRIVERS_TOOLS
MONGODB_BINARIES=$MONGODB_BINARIES
MONGO_ORCHESTRATION_HOME=$MONGO_ORCHESTRATION_HOME
PROJECT_ORCHESTRATION_HOME=$PROJECT_ORCHESTRATION_HOME
CURRENT_VERSION=$CURRENT_VERSION
OS=${OS:-}
PATH=$PATH
EOF
