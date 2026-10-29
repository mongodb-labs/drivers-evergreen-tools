#!/usr/bin/env bash
set -eu

# Fail if the image does not have a working pip; ensure_uv expects one and the
# venv fallback would otherwise mask a missing install.
python3 -m pip --version >/dev/null

bash /root/base-entrypoint.sh
source $DRIVERS_TOOLS/mo-expansion.sh
URI="mongodb://127.0.0.1:27017/?serverSelectionTimeoutMS=10000"
$MONGODB_BINARIES/mongosh $URI --eval "db.runCommand({\"ping\":1})"
echo "Test complete!"
