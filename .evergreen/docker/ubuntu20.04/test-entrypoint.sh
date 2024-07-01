#!/usr/bin/env bash
set -eux

bash /root/base-entrypoint.sh
source $DRIVERS_TOOLS/.evergreen/mo-expansion.sh
URI="mongodb://127.0.0.1:27017/?serverSelectionTimeoutMS=10000"
$MONGODB_BINARIES/mongosh $URI --eval "db.runCommand({\"ping\":1})"
echo "Test complete!"
