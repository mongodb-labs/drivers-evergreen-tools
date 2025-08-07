#!/usr/bin/env bash
# Handle setup for orchestration

set -o errexit

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPT_DIR:?}/../handle-paths.sh"

export DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES
DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES="${SCRIPT_DIR:?}/uv-override-dependencies.txt"
printf "">|"${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:?}"

# Preserve pymongo compatibility with the requested server version.
case "${MONGODB_VERSION:-"latest"}" in
3.6) echo "pymongo<4.11" >>"${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:?}" ;;
4.0) echo "pymongo<4.14" >>"${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:?}" ;;
esac

# Install CLIs into this directory (default path for $PROJECT_ORCHESTRATION_HOME
# and $MONGO_ORCHESTRATION_HOME) and the parent directory ($DRIVERS_TOOLS).
bash "${SCRIPT_DIR:?}/../install-cli.sh" "${SCRIPT_DIR:?}/.."
bash "${SCRIPT_DIR:?}/../install-cli.sh" "${SCRIPT_DIR:?}"
