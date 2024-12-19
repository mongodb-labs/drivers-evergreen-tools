#!/usr/bin/env bash
set -eu

bash $ENTRYPOINTS/base-entrypoint.sh
source $DRIVERS_TOOLS/mo-expansion.sh
URI="mongodb://127.0.0.1:27017/?serverSelectionTimeoutMS=10000"
$MONGODB_BINARIES/mongosh $URI --eval "db.runCommand({\"ping\":1})"
echo "Test complete!"
