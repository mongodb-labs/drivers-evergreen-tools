#!/usr/bin/env bash
#
# Entry point for Dockerfile for launching an oidc-enabled server.
#
set -eu
export ORCHESTRATION_FILE=auth-oidc.json

rm -f $DRIVERS_TOOLS/results.json
cd $DRIVERS_TOOLS/.evergreen/auth_oidc
# The auth_oidc group lives in the root pyproject.toml.
. $DRIVERS_TOOLS/.evergreen/ensure-uv.sh
ensure_uv || exit 1
uv run --project "$DRIVERS_TOOLS" --group auth_oidc python oidc_write_orchestration.py

bash /root/base-entrypoint.sh

$MONGODB_BINARIES/mongosh -f $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js "mongodb://127.0.0.1:27017/directConnection=true&serverSelectionTimeoutMS=10000"

echo "Server started!"
