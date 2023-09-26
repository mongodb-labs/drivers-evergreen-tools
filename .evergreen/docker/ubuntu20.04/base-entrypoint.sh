#!/usr/bin/env bash
set -eu

rm -f $DRIVERS_TOOLS/results.json
cd $DRIVERS_TOOLS/.evergreen
bash run-orchestration.sh

# Change permissions of files we have created.
cd $DRIVERS_TOOLS
files="results.json uri.txt .evergreen/mongo_crypt_v1.so"
for fname in $files; do
    chown --reference=action.yml $fname
    chmod --reference=action.yml $fname
done

echo "Server started!"
