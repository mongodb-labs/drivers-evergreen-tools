#!/usr/bin/env bash
set -eu

bash /root/base-entrypoint.sh
source $DRIVERS_TOOLS/.evergreen/mo-expansion.sh
$MONGODB_BINARIES/mongosh --eval 'db'
echo "Test complete!"
