#!/usr/bin/env bash
#
# activate-authawsvenv.sh
#
# Usage:
#   . ./activate-authawsvenv.sh
#
# Creates and/or activates the Python environment for the auth_aws test
# scripts: the root workspace .venv with the auth_aws group (pymongo[aws],
# boto3, pyop). Delegates to the shared helper, ../activate-uv-venv.sh.

if [ -z "$BASH" ]; then
  echo "activate-authawsvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# shellcheck source=.evergreen/activate-uv-venv.sh
. "$(dirname "${BASH_SOURCE[0]}")/../activate-uv-venv.sh" || return 1

activate_uv_venv auth_aws
