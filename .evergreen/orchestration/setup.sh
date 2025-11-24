#!/usr/bin/env bash
# Handle setup for orchestration

set -o errexit

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
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

# Install the in-progress branch of mongodb-runner.
if [ ! -d $SCRIPT_DIR/devtools-shared ]; then
  git clone -b extra-params https://github.com/mongodb-js/devtools-shared
  npm init -y
  pushd $SCRIPT_DIR/devtools-shared
  npm run bootstrap-ci -- --scope @mongodb-js/monorepo-tools --stream --include-dependencies
  npm run bootstrap-ci -- --stream --include-dependencies
  popd
  npm install ./devtools-shared/packages/mongodb-runner
fi
