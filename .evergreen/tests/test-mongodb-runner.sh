#!/usr/bin/env bash

# Test usage of start-server.sh
set -eu -o pipefail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
. $SCRIPT_DIR/../ensure-uv.sh

pushd $SCRIPT_DIR/.. > /dev/null

. ./init-node-and-npm-env.sh

# Connect to the MongoDB server using tls
# shellcheck disable=SC2120
function connect_mongodb() {
  local use_tls=false
  local use_auth=false
  local eval_cmd='db.runCommand({"ping":1})'

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ssl) use_tls=true; shift ;;
      --auth) use_auth=true; shift ;;
      --eval-cmd)
        if [[ -z "${2:-}" ]]; then
          echo "Missing value for --eval-cmd"
          return 1
        fi
        eval_cmd="$2"
        shift 2
        ;;
      *) echo "Unknown option: $1"; return 1 ;;
    esac
  done

  URI="mongodb://localhost:27017/?directConnection=true&serverSelectionTimeoutMS=10000"
  if [[ "$use_auth" == "true" ]]; then
    URI="mongodb://bob:pwd123@localhost:27017/?directConnection=true&serverSelectionTimeoutMS=10000&authSource=admin"
  fi
  local TLS_OPTS=()
  if [[ "$use_tls" == "true" ]]; then
    TLS_OPTS+=("--tls" "--tlsCertificateKeyFile" "${DRIVERS_TOOLS}/.evergreen/x509gen/server.pem")
    TLS_OPTS+=("--tlsCAFile" "${DRIVERS_TOOLS}/.evergreen/x509gen/ca.pem")
  fi
  local result=0
  echo "Connecting to server..."
  # shellcheck disable=SC2068
  $MONGODB_BINARIES/mongosh "$URI" ${TLS_OPTS[@]:-} --eval "$eval_cmd" || result=$?
  echo "Connecting to server... done."
  return $result
}

# Start a deployment and fail unless mongodb-runner started it, or the host is one
# where mongodb-runner is known not to run at all (old glibc capping Node below what
# the current mongodb-runner needs, see install-node.sh). A silent fallback on a host
# that could have used mongodb-runner would hide a broken pin set; a fallback on a
# host that never could is the designed behavior from DRIVERS-3558.
function start_with_runner() {
  local log
  log=$(mktemp)
  # Clean up the temp log on function return without leaving a RETURN trap installed.
  trap 'rm -f "$log"; trap - RETURN' RETURN

  if ! bash ./run-mongodb.sh start "$@" 2>&1 | tee "$log"; then
    echo "ERROR: 'run-mongodb.sh start $*' failed"
    return 1
  fi

  if grep -q "Running mongodb-runner using" "$log"; then
    return 0
  fi
  if grep -q "mongodb-runner is not supported on this platform" "$log"; then
    echo "NOTE: mongodb-runner is unsupported here; started through mongo-orchestration instead"
    return 0
  fi
  echo "ERROR: 'run-mongodb.sh start $*' did not start through mongodb-runner"
  return 1
}

# Test for default, then test cli options.
start_with_runner
connect_mongodb

bash ./run-mongodb.sh start --topology standalone --auth
connect_mongodb --auth

bash ./run-mongodb.sh start --version 7.0 --topology replica_set --ssl
connect_mongodb --ssl

bash ./run-mongodb.sh start --version latest --topology sharded_cluster --auth --ssl
connect_mongodb --ssl --auth

# Verify that auth is enforced when starting with AUTH=auth SSL=yes.
# An unauthenticated connection must be rejected, and an authenticated one must succeed.
AUTH=auth SSL=yes bash ./run-mongodb.sh start
if connect_mongodb --ssl --eval-cmd 'db.adminCommand({listDatabases:1})' 2>/dev/null; then
  echo "ERROR: unauthenticated connection should have been rejected on an auth+ssl server"
  exit 1
fi
connect_mongodb --ssl --auth

# Ensure that we can use a downloaded mongodb directory.
DOWNLOAD_DIR=mongodl_test
rm -rf ${DOWNLOAD_DIR}
bash install-cli.sh "$(pwd)/orchestration"
ensure_uv || exit 1
uv run python mongodl.py --edition enterprise --version 7.0 --component archive --out ${DOWNLOAD_DIR} --strip-path-components 2 --retries 5
bash ./run-mongodb.sh start --existing-binaries-dir=${DOWNLOAD_DIR}
${DOWNLOAD_DIR}/mongod --version | grep v7.0

if [ "${1:-}" == "partial" ]; then
  popd > /dev/null
  make -C ${DRIVERS_TOOLS} test
  exit 0
fi

for version in rapid 8.0 6.0 5.0 4.4
do
  bash ./run-mongodb.sh start --version "$version"
  connect_mongodb
done

# 4.2 predates the wire version the current Node driver requires, so it only starts
# if the per-version pin held.
start_with_runner --version 4.2
connect_mongodb

popd > /dev/null
make -C ${DRIVERS_TOOLS} test
