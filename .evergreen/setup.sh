#!/usr/bin/env bash
# Handle common test setup for drivers-tools.

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh
. $SCRIPT_DIR/ensure-uv.sh

# Some hosts (e.g. rhel8-zseries/s390x) have their CA trust store in a
# location that uv's managed Python builds and Node don't discover by
# default, causing SSL_CERT_VERIFY_FAILED for any HTTPS request they make
# (e.g. mongodl.py, mongodb-runner). Point Python (SSL_CERT_FILE) and Node
# (NODE_EXTRA_CA_CERTS) at the system bundle explicitly, and persist it to
# .env so every later task step (each a fresh shell) picks it up via
# handle-paths.sh.
if [ -z "${SSL_CERT_FILE:-}" ]; then
  for _cert_file in /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem; do
    if [ -f "$_cert_file" ]; then
      export SSL_CERT_FILE="$_cert_file"
      export NODE_EXTRA_CA_CERTS="$_cert_file"
      {
        echo "SSL_CERT_FILE=$_cert_file"
        echo "NODE_EXTRA_CA_CERTS=$_cert_file"
      } >>"$DRIVERS_TOOLS/.env"
      break
    fi
  done
fi

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

# Setup the orchestration directory, which also installs CLIs into this directory.
bash $SCRIPT_DIR/orchestration/setup.sh
