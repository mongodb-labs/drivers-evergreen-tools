#!/usr/bin/env bash
set -eu

rm -f $DRIVERS_TOOLS/results.json
cd $DRIVERS_TOOLS/.evergreen
bash run-orchestration.sh

# Change permissions of files we have created.
cd $DRIVERS_TOOLS
chown --reference=action.yml results.json
chmod --reference=action.yml results.json
chown --reference=action.yml uri.txt
chmod --reference=action.yml uri.txt

echo "Server started!"
