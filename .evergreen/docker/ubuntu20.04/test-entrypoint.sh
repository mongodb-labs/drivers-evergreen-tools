#!/usr/bin/env bash
set -eux

bash /root/base-entrypoint.sh
source $DRIVERS_TOOLS/.evergreen/mo-expansion.sh
$MONGODB_BINARIES/mongosh --eval "db.runCommand({\"ping\":1})" --&serverSelectionTimeoutMS=10000
echo "Test complete!"
