#!/usr/bin/env bash
set -eu

cd $DRIVERS_TOOLS/.evergreen
bash run-orchestration.sh
echo "Success!"
