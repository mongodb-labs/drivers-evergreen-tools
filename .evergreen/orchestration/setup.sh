#!/usr/bin/env bash
# Handle setup for orchestration

set -o errexit

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
_HERE=${SCRIPT_DIR}
. "${SCRIPT_DIR:?}/../handle-paths.sh"

export DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES
DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES="${SCRIPT_DIR:?}/uv-override-dependencies.txt"
printf "" >|"${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:?}"

# Preserve pymongo compatibility with the requested server version.
case "${MONGODB_VERSION:-"latest"}" in
3.6) echo "pymongo<4.11" >>"${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:?}" ;;
4.0) echo "pymongo<4.14" >>"${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:?}" ;;
esac

# Install CLIs into this directory (default path for $PROJECT_ORCHESTRATION_HOME
# and $MONGO_ORCHESTRATION_HOME) and the parent directory ($DRIVERS_TOOLS).
bash "${SCRIPT_DIR:?}/../install-cli.sh" "${SCRIPT_DIR:?}/.."
bash "${SCRIPT_DIR:?}/../install-cli.sh" "${SCRIPT_DIR:?}"

# Install the in-progress branch of mongodb-runner if USE_DEV_MONGODB_RUNNER is set.
# TODO: remove before merging
export USE_DEV_MONGODB_RUNNER=1
if [ -n "${USE_DEV_MONGODB_RUNNER:-}" ]; then
  if [ ! -d "$HERE/../node-artifacts" ]; then
    # The dev version requires Node 22+.
    NODE_LTS_VERSION=22 bash $_HERE/../install-node.sh
  fi

  if [ ! -d $_HERE/devtools-shared ]; then
    source $_HERE/../init-node-and-npm-env.sh
    git clone -b make-host-settable-sharded https://github.com/blink1073/devtools-shared $_HERE/devtools-shared
    pushd $_HERE/devtools-shared
    npm install --ignore-scripts
    npx -y lerna run --scope=mongodb-runner --include-dependencies compile
    popd
  fi
else
  bash $_HERE/../install-node.sh
fi
