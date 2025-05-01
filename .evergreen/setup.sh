#!/usr/bin/env bash
# Handle common test setup for drivers-tools.

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh
. $SCRIPT_DIR/find-python3.sh

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

# Set the python binary to use.
DRIVERS_TOOLS_PYTHON="$(ensure_python3 2>/dev/null)"
echo "DRIVERS_TOOLS_PYTHON=$DRIVERS_TOOLS_PYTHON" >> $DRIVERS_TOOLS/.env

# Set up the orchestration folder, which also installs CLIs in this folder.
# We do this is because it uses some of the CLIs in this folder.
bash $SCRIPT_DIR/orchestration/setup.sh
