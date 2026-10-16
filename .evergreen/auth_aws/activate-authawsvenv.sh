#!/usr/bin/env bash
#
# activate-authawsvenv.sh
#
# Usage:
#   . ./activate-authawsvenv.sh
#
# Creates and/or activates the Python environment for the auth_aws test
# scripts, leaving `python` pointing at an environment with the auth_aws
# dependencies (pymongo[aws], boto3, pyop). The environment is the root uv
# workspace's .venv, built from the auth_aws group in the root pyproject.toml.
# May be invoked from any working directory. On error, nothing is left
# activated and the script returns non-zero.
#
# Delegates to the shared helper, ../activate-uv-venv.sh.

if [ -z "$BASH" ]; then
  echo "activate-authawsvenv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# shellcheck source=.evergreen/activate-uv-venv.sh
. "$(dirname "${BASH_SOURCE[0]}")/../activate-uv-venv.sh" || return 1

activate_uv_venv auth_aws
