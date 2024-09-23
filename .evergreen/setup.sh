#!/usr/bin/env bash
# Handle common test setup for drivers-tools.

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

# Ensure environment variables are set.
if [[ -z "$PROJECT_DIRECTORY" ]]; then
  echo "Please set the PROJECT_DIRECTORY environment variable."
  exit 1
fi

# Create failing test result file.
echo '{"results": [{ "status": "FAIL", "test_file": "Build", "log_raw": "No test-results.json found was created"  } ]}' > ${PROJECT_DIRECTORY}/test-results.json

# Create a stub mongo-orchestration results file.
echo '{"results": [{ "status": "PASS", "test_file": "Build", "log_raw": "Stub file for mongo-orchestration results"  } ]}' > ${DRIVERS_TOOLS}/results.json

# Ensure there is at least one log file.
cat << EOF > ${DRIVERS_TOOLS}/.evergreen/inputs.log
PROJECT_DIRECTORY=$PROJECT_DIRECTORY
DRIVERS_TOOLS=$DRIVERS_TOOLS
OS=${OS:-}
PATH=$PATH
EOF
