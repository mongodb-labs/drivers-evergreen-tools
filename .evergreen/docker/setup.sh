#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Source secrets from the vault.
if [ ! -f secrets-export.sh ]; then
  . $SCRIPT_DIR/../secrets_handling/setup-secrets.sh drivers/docker
fi
source secrets-export.sh

# Python script that uses boto3 to assume the role and get the login password, then passes it to docker login
. $SCRIPT_DIR/../ensure-uv.sh
ensure_uv || exit 1
# The docker group is defined in the root pyproject.toml, so run from the
# root project context. DRIVERS_TOOLS is set absolutely by handle-paths.sh.
uv run --project "$DRIVERS_TOOLS" --group docker python login.py
