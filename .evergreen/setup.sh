#!/usr/bin/env bash
# Handle common test setup for drivers-tools.

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh
. $SCRIPT_DIR/ensure-uv.sh
# For ensure_python3, used to seed DRIVERS_TOOLS_PYTHON below.
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

# Ensure uv is available for the CLI install step below.
ensure_uv || exit 1

# Set the python binary to use, for the per-folder virtualenv scripts (auth_aws,
# auth_oidc, csfle, docker, ocsp) that are still on the find-python3.sh
# mechanism, and for downstream repos that read this from .env.
#
# This must come from ensure_python3, not from uv. ensure_python3 selects in a
# specific order (toolchain, then `python3`, then `python`) and the value is fed
# to venvcreate, which passes --system-site-packages. Resolving it with uv
# instead picks /usr/bin/python (3.10) in the Ubuntu test image where
# find_python3 correctly picks python3 (3.11), and the 3.10 dist-packages then
# leak a stale pyOpenSSL into the venv.
DRIVERS_TOOLS_PYTHON="$(ensure_python3 2>/dev/null)"
echo "DRIVERS_TOOLS_PYTHON=$DRIVERS_TOOLS_PYTHON" >> $DRIVERS_TOOLS/.env

# Setup the orchestration directory, which also installs CLIs into this directory.
bash $SCRIPT_DIR/orchestration/setup.sh
